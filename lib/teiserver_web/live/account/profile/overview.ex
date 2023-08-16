defmodule TeiserverWeb.Account.ProfileLive.Overview do
  @moduledoc false
  use TeiserverWeb, :live_view
  alias Teiserver.Account

  @impl true
  def mount(%{"userid" => userid_str}, _session, socket) do
    userid = String.to_integer(userid_str)
    user = Account.get_user_by_id(userid)

    socket = cond do
      user == nil ->
        socket
          |> put_flash(:info, "Unable to find that user")
          |> redirect(to: ~p"/")

      true ->
        socket
          |> assign(:tab, nil)
          |> assign(:site_menu_active, "teiserver_account")
          |> assign(:view_colour, Teiserver.Account.UserLib.colours())
          |> assign(:user, user)
          |> assign(:role_data, Account.RoleLib.role_data())
          |> get_relationships
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(%{assigns: %{user: user}} = socket, :overview, _params) do
    socket
      |> assign(:page_title, "#{user.name} - Overview")
  end

  defp apply_action(%{assigns: %{user: user}} = socket, :accolades, _params) do
    socket
      |> assign(:page_title, "#{user.name} - Accolades")
  end

  defp apply_action(%{assigns: %{user: user}} = socket, :achievements, _params) do
    socket
      |> assign(:page_title, "#{user.name} - Achievements")
  end

  @impl true
  def handle_event("follow-user", _event, %{assigns: %{current_user: current_user, user: user}} = socket) do
    Account.follow_user(current_user.id, user.id)

    socket = socket
      |> put_flash(:success, "You are now following #{user.name}")
      |> get_relationships()

    {:noreply, socket}
  end

  def handle_event("reset-relationship-state", _event, %{assigns: %{current_user: current_user, user: user}} = socket) do
    Account.reset_relationship_state(current_user.id, user.id)

    socket = socket
      |> put_flash(:success, "You are now no longer following, ignoring, avoiding or blocking #{user.name}")
      |> get_relationships()

    {:noreply, socket}
  end

  def handle_event("ignore-user", _event, %{assigns: %{current_user: current_user, user: user}} = socket) do
    Account.ignore_user(current_user.id, user.id)

    socket = socket
      |> put_flash(:success, "You are now ignoring #{user.name}")
      |> get_relationships()

    {:noreply, socket}
  end

  def handle_event("avoid-user", _event, %{assigns: %{current_user: current_user, user: user}} = socket) do
    Account.avoid_user(current_user.id, user.id)

    socket = socket
      |> put_flash(:success, "You are now avoiding #{user.name}")
      |> get_relationships()

    {:noreply, socket}
  end

  def handle_event("block-user", _event, %{assigns: %{current_user: current_user, user: user}} = socket) do
    Account.block_user(current_user.id, user.id)

    socket = socket
      |> put_flash(:success, "You are now blocking #{user.name}")
      |> get_relationships()

    {:noreply, socket}
  end

  def handle_event("unfriend-user", _event, %{assigns: %{current_user: current_user, user: user}} = socket) do
    Account.decline_friend_request(current_user.id, user.id)

    socket = socket
      |> put_flash(:success, "Request from #{user.name} declined")
      |> get_relationships()

    {:noreply, socket}
  end

  def handle_event("accept-friend-request", _event, %{assigns: %{current_user: current_user, user: user}} = socket) do
    Account.accept_friend_request(current_user.id, user.id)

    socket = socket
      |> put_flash(:success, "Request accepted, you are now friends with #{user.name}")
      |> get_relationships()

    {:noreply, socket}
  end

  def handle_event("rescind-friend-request", _event, %{assigns: %{current_user: current_user, user: user}} = socket) do
    Account.rescind_friend_request(current_user.id, user.id)

    socket = socket
      |> put_flash(:success, "Friend request rescinded")
      |> get_relationships()

    {:noreply, socket}
  end

  def handle_event("create-friend-request", _event, %{assigns: %{current_user: current_user, user: user}} = socket) do
    Account.create_friend_request(current_user.id, user.id)

    socket = socket
      |> put_flash(:success, "Friend request sent")
      |> get_relationships()

    {:noreply, socket}
  end

  defp get_relationships(%{assigns: %{current_user: current_user, user: user}} = socket) do
    relationship = Account.get_relationship(current_user.id, user.id)
    friendship = Account.get_friend(current_user.id, user.id)
    friendship_request = Account.get_friend_request(nil, nil, [where: [either_user_is: {current_user.id, user.id}]])

    socket
      |> assign(:relationship, relationship)
      |> assign(:friendship, friendship)
      |> assign(:friendship_request, friendship_request)
  end
end
