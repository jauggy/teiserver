defmodule Teiserver.Player.Session do
  @moduledoc """
  A session has a link to a player connection, but can outlive it.
  This is a separate process that should be used to check whether a player
  is online.

  It holds very minimal state regarding the connection.
  """

  use GenServer
  require Logger

  alias Teiserver.Data.Types, as: T
  alias Teiserver.{Player, Matchmaking}

  @type conn_state :: :connected | :reconnecting | :disconnected

  @type matchmaking_state ::
          :no_matchmaking
          | {:searching,
             %{
               joined_queues: nonempty_list(Matchmaking.queue_id())
             }}
          | {:pairing,
             %{
               paired_queue: Matchmaking.queue_id(),
               room: {pid(), reference()},
               # a list of the other queues to rejoin in case the pairing fails
               frozen_queues: [Matchmaking.queue_id()],
               readied: boolean()
             }}

  @type state :: %{
          user_id: T.userid(),
          mon_ref: reference(),
          conn_pid: pid() | nil,
          matchmaking: matchmaking_state()
        }

  @spec conn_state(T.userid()) :: conn_state()
  def conn_state(user_id) do
    GenServer.call(via_tuple(user_id), :conn_state)
  catch
    :exit, {:noproc, _} ->
      :disconnected
  end

  @doc """
  Cleanly disconnect the user, clearing any state
  """
  @spec disconnect(T.userid()) :: :ok
  def disconnect(user_id) do
    # the registry will automatically unregister when the process terminates
    # but that can lead to race conditions when a player disconnect and
    # reconnect immediately
    Player.SessionRegistry.unregister(user_id)
    GenServer.call(via_tuple(user_id), :disconnect)
  end

  @spec join_queues(T.userid(), [Matchmaking.queue_id()]) :: Matchmaking.join_result()
  def join_queues(user_id, queue_ids) do
    GenServer.call(via_tuple(user_id), {:join_queues, queue_ids})
  end

  @doc """
  Leave all the queues, and effectively removes the player from any matchmaking
  """
  @spec leave_queues(T.userid()) :: Matchmaking.leave_result()
  def leave_queues(user_id) do
    GenServer.call(via_tuple(user_id), :leave_queues)
  end

  @doc """
  A match has been found and the player is expected to ready up
  """
  @spec matchmaking_notify_found(T.userid(), Matchmaking.queue_id(), pid(), timeout()) :: :ok
  def matchmaking_notify_found(user_id, queue_id, room_pid, timeout_ms) do
    GenServer.cast(
      via_tuple(user_id),
      {:matchmaking_notify_found, queue_id, room_pid, timeout_ms}
    )
  end

  @doc """
  The player is ready for the match
  """
  @spec matchmaking_ready(T.userid()) :: :ok | {:error, :no_match}
  def matchmaking_ready(user_id) do
    GenServer.call(via_tuple(user_id), :matchmaking_ready)
  end

  @spec matchmaking_lost(T.userid(), Matchmaking.lost_reason()) :: :ok
  def matchmaking_lost(user_id, reason) do
    GenServer.cast(via_tuple(user_id), {:matchmaking_lost, reason})
  end

  @spec matchmaking_found_update(T.userid(), non_neg_integer(), pid()) :: :ok
  def matchmaking_found_update(user_id, ready_count, room_pid) do
    GenServer.cast(via_tuple(user_id), {:matchmaking_found_update, ready_count, room_pid})
  end

  def start_link({_conn_pid, user_id} = arg) do
    GenServer.start_link(__MODULE__, arg, name: via_tuple(user_id))
  end

  @doc """
  To forcefully disconnect a connected player and replace this connection
  with another one. This is to avoid having the same player with several
  connections.
  """
  @spec replace_connection(pid(), pid()) :: :ok | :died
  def replace_connection(sess_pid, new_conn_pid) do
    GenServer.call(sess_pid, {:replace, new_conn_pid})
  catch
    :exit, _ ->
      :died
  end

  @impl true
  def init({conn_pid, user_id}) do
    ref = Process.monitor(conn_pid)

    state = %{
      user_id: user_id,
      mon_ref: ref,
      conn_pid: conn_pid,
      matchmaking: initial_matchmaking_state()
    }

    {:ok, state}
  end

  defp initial_matchmaking_state() do
    :no_matchmaking
  end

  @impl true
  def handle_call({:replace, _}, _from, state) when is_nil(state.conn_pid),
    do: {:reply, :ok, state}

  def handle_call({:replace, new_conn_pid}, _from, state) do
    Process.demonitor(state.mon_ref, [:flush])

    mon_ref = Process.monitor(new_conn_pid)

    {:reply, :ok, %{state | conn_pid: new_conn_pid, mon_ref: mon_ref}}
  end

  def handle_call(:conn_state, _from, state) do
    result = if is_nil(state.conn_pid), do: :reconnecting, else: :connected
    {:reply, result, state}
  end

  def handle_call(:disconnect, _from, state) do
    user_id = state.user_id

    case state.matchmaking do
      {:searching, %{joined_queues: joined_queues}} ->
        Enum.each(joined_queues, fn queue_id ->
          Matchmaking.QueueServer.leave_queue(queue_id, user_id)
        end)

      _ ->
        nil
    end

    {:stop, :normal, :ok, %{state | matchmaking: initial_matchmaking_state()}}
  end

  # this should never happen because the json schema already checks for minimum length
  def handle_call({:join_queues, []}, _from, state),
    do: {:reply, {:error, :invalid_request}, state}

  def handle_call({:join_queues, queue_ids}, _from, state) do
    case state.matchmaking do
      :no_matchmaking ->
        case join_all_queues(state.user_id, queue_ids, []) do
          :ok ->
            new_mm_state = {:searching, %{joined_queues: queue_ids}}
            {:reply, :ok, put_in(state.matchmaking, new_mm_state)}

          {:error, err} ->
            {:reply, {:error, err}, state}
        end

      {:searching, _} ->
        {:reply, {:error, :already_queued}, state}

      {:pairing, _} ->
        {:reply, {:error, :already_queued}, state}
    end
  end

  def handle_call(:leave_queues, _from, state) do
    case state.matchmaking do
      :no_matchmaking ->
        {:reply, {:error, :not_queued}, state}

      {:searching, %{joined_queues: joined_queues}} ->
        new_state = leave_all_queues(joined_queues, state)
        {:reply, :ok, new_state}

      {:pairing, %{room: {_, room_ref}} = pairing_state} ->
        Process.demonitor(room_ref, [:flush])
        queues_to_leave = [pairing_state.paired_queue | pairing_state.frozen_queues]
        new_state = leave_all_queues(queues_to_leave, state)
        {:reply, :ok, new_state}
    end
  end

  def handle_call(:matchmaking_ready, _from, state) do
    case state.matchmaking do
      {:pairing, %{room: {room_pid, _}} = pairing_state} ->
        new_state = %{state | matchmaking: {:pairing, %{pairing_state | readied: true}}}
        {:reply, Matchmaking.ready(room_pid, state.user_id), new_state}

      _ ->
        {:reply, {:error, :no_match}, state}
    end
  end

  @impl true
  def handle_cast(
        {:matchmaking_notify_found, queue_id, room_pid, timeout_ms},
        %{matchmaking: {:searching, %{joined_queues: queue_ids}}} = state
      ) do
    if not Enum.member?(queue_ids, queue_id) do
      {:noreply, state}
    else
      state = send_to_player({:matchmaking_notify_found, queue_id, timeout_ms}, state)

      other_queues =
        for qid <- queue_ids, qid != queue_id do
          Matchmaking.leave_queue(qid, state.user_id)
          qid
        end

      room_ref = Process.monitor(room_pid)

      new_mm_state =
        {:pairing,
         %{
           paired_queue: queue_id,
           room: {room_pid, room_ref},
           frozen_queues: other_queues,
           readied: false
         }}

      new_state = Map.put(state, :matchmaking, new_mm_state)
      {:noreply, new_state}
    end
  end

  def handle_cast({:matchmaking_notify_found, _queue_id, _}, state) do
    # we're not searching anything. This can happen as a race when two queues
    # match the same player at the same time.
    # TODO tachyon_mvp: need to decline the pairing here
    {:noreply, state}
  end

  def handle_cast({:matchmaking_lost, reason}, state) do
    case state.matchmaking do
      :no_matchmaking ->
        {:noreply, state}

      {:searching, _} ->
        state = send_to_player(:matchmaking_notify_lost, state)
        {:noreply, state}

      {:pairing,
       %{paired_queue: q_id, room: {_, ref}, frozen_queues: frozen_queues, readied: readied}} ->
        Process.demonitor(ref, [:flush])
        q_ids = [q_id | frozen_queues]
        state = send_to_player(:matchmaking_notify_lost, state)

        if reason == :timeout && not readied do
          state = leave_all_queues(q_ids, state)
          state = send_to_player({:matchmaking_cancelled, reason}, state)
          {:noreply, state}
        else
          case join_all_queues(state.user_id, q_ids, []) do
            :ok ->
              new_mm_state = {:searching, %{joined_queues: q_ids}}
              {:noreply, put_in(state.matchmaking, new_mm_state)}

            {:error, _err} ->
              state = send_to_player({:matchmaking_cancelled, :server_error}, state)
              {:noreply, %{state | matchmaking: initial_matchmaking_state()}}
          end
        end
    end
  end

  def handle_cast({:matchmaking_found_update, current, room_pid}, state) do
    case state.matchmaking do
      {:pairing, %{room: {^room_pid, _}}} ->
        {:noreply, send_to_player({:matchmaking_found_update, current}, state)}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _, _reason}, state) when ref == state.mon_ref do
    # we don't care about cancelling the timer if the player reconnects since reconnection
    # should be fairly low (and rate limited) so too many messages isn't an issue
    {:ok, _} = :timer.send_after(30_000, :player_timeout)
    {:noreply, %{state | conn_pid: nil}}
  end

  def handle_info({:DOWN, ref, :process, _obj, reason}, state) do
    case state do
      %{matchmaking: {:pairing, %{room: {_, ^ref}}}} ->
        # only log in case of abnormal exit. If the queue itself goes down, so be it
        if reason != :shutdown, do: Logger.warning("Pairing room went down #{inspect(reason)}")
        # TODO tachyon_mvp: rejoin the room and send `lost` event
        # For now, just abruptly stop everything
        {:stop, :normal, state}

      st ->
        if reason != :normal do
          Logger.warning(
            "unhandled DOWN: #{inspect(ref)} went down because #{reason}. state: #{inspect(st)}"
          )
        end

        {:noreply, state}
    end
  end

  def handle_info(:player_timeout, state) do
    if is_nil(state.conn_pid) do
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  defp via_tuple(user_id) do
    Player.SessionRegistry.via_tuple(user_id)
  end

  @spec join_all_queues(T.userid(), [Matchmaking.queue_id()], [Matchmaking.queue_id()]) ::
          Matchmaking.join_result()
  defp join_all_queues(_user_id, [], _joined), do: :ok

  defp join_all_queues(user_id, [to_join | rest], joined) do
    case Matchmaking.join_queue(to_join, user_id) do
      :ok ->
        join_all_queues(user_id, rest, [to_join | joined])

      # the `queue` message is all or nothing, so if joining a later queue need
      # to leave the queues already joined
      {:error, reason} ->
        Enum.each(joined, fn qid -> Matchmaking.leave_queue(qid, user_id) end)

        {:error, reason}
    end
  end

  defp leave_all_queues(queues_to_leave, state) do
    # TODO tachyon_mvp: leaving queue ignore failure there.
    # It is a bit unclear what kind of failure can happen, and also
    # what should be done in that case
    Enum.each(queues_to_leave, fn qid ->
      Matchmaking.leave_queue(qid, state.user_id)
    end)

    Map.put(state, :matchmaking, initial_matchmaking_state())
  end

  defp send_to_player(message, state) do
    # TODO tachyon_mvp: what should server do if the connection is down at that time?
    # The best is likely to store it and send the notification upon reconnection
    if state.conn_pid != nil do
      send(state.conn_pid, message)
    end

    state
  end
end
