defmodule Teiserver.Account.PartyLib do
  alias Phoenix.PubSub
  alias Teiserver.{Account, Battle}
  alias Teiserver.Party
  alias Teiserver.Data.Types, as: T

  @spec colours() :: atom
  def colours, do: :primary2

  @spec icon() :: String.t()
  def icon, do: "fa-solid fa-people-group"

  # Retrieval
  @spec get_party(nil) :: nil
  @spec get_party(T.party_id()) :: nil | T.party()
  def get_party(nil), do: nil
  def get_party(party_id) do
    call_party(party_id, :party_state)
  end

  @spec list_party_ids() :: [T.party_id()]
  def list_party_ids() do
    Horde.Registry.select(Teiserver.PartyRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @spec list_parties() :: [T.party()]
  def list_parties() do
    list_party_ids()
      |> list_parties()
  end

  @spec list_parties([T.party_id()]) :: [T.party()]
  def list_parties(id_list) do
    id_list
      |> Enum.map(fn c -> get_party(c) end)
  end

  # Updates
  @spec replace_update_party(Map.t()) :: :ok | nil
  def replace_update_party(%{id: id} = party) do
    cast_party(id, {:update_party, party})
  end


  # Process stuff
  @spec start_party_server(T.lobby()) :: pid()
  def start_party_server(party) do
    {:ok, server_pid} =
      DynamicSupervisor.start_child(Teiserver.PartySupervisor, {
        Teiserver.Account.PartyServer,
        name: "party_#{party.party_id}",
        data: %{
          party: party
        }
      })

    server_pid
  end

  @spec get_party_pid(T.party_id()) :: pid() | nil
  def get_party_pid(party_id) do
    case Horde.Registry.lookup(Teiserver.PartyRegistry, party_id) do
      [{pid, _}] -> pid
      _ -> nil
    end
  end

  @spec cast_party(T.party_id(), any) :: any
  def cast_party(party_id, msg) do
    case get_party_pid(party_id) do
      nil -> nil
      pid -> GenServer.cast(pid, msg)
    end
  end

  @spec call_party(T.party_id(), any) :: any | nil
  def call_party(party_id, msg) do
    case get_party_pid(party_id) do
      nil -> nil
      pid -> GenServer.call(pid, msg)
    end
  end
end