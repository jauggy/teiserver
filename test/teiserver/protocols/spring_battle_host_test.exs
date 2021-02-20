defmodule Teiserver.SpringBattleHostTest do
  use Central.ServerCase
  require Logger
  # alias Teiserver.BitParse
  # alias Teiserver.User
  alias Teiserver.Battle
  import Central.Helpers.NumberHelper, only: [int_parse: 1]
  import Teiserver.TestLib, only: [auth_setup: 0, auth_setup: 1, _send: 2, _recv: 1, new_user: 0]

  setup do
    %{socket: socket, user: user} = auth_setup()
    {:ok, socket: socket, user: user}
  end

  test "host battle test", %{socket: socket} do
    _send(socket, "OPENBATTLE 0 0 empty 322 16 gameHash 0 mapHash engineName\tengineVersion\tmapName\tgameTitle\tgameName\n")
    part1 = _recv(socket)
    part2 = _recv(socket)
    :timeout = _recv(socket)

    reply =
      (part1 <> part2)
      |> String.split("\n")

    [
      _open,
      join,
      _tags,
      rect1,
      rect2,
      battle_status,
      _saidbattle,
      _joinedbattle,
      _clientstatus
      | _
    ] = reply

    assert join =~ "JOINBATTLE "
    assert join =~ " gameHash"
    battle_id = join
      |> String.replace("JOINBATTLE ", "")
      |> String.replace(" gameHash", "")
      |> int_parse
    assert rect1 == "ADDSTARTRECT 0 0 126 74 200"
    assert rect2 == "ADDSTARTRECT 1 126 0 200 74"
    assert battle_status == "REQUESTBATTLESTATUS"

    # Check the battle actually got created
    battle = Battle.get_battle(battle_id)
    assert battle != nil

    # Now create a user to join the battle
    user2 = new_user()
    %{socket: socket2} = auth_setup(user2)
    _send(socket2, "JOINBATTLE 3 empty gameHash\n")
    # The response to joining a battle is tested elsewhere, we just care about the host right now
    _ = _recv(socket2)

    reply = _recv(socket)
    assert reply =~ "ADDUSER #{user2.name} XX #{user2.id}\tLuaLobby Chobby\n"
    assert reply =~ "JOINEDBATTLE 3 #{user2.name}\n"
    assert reply =~ "CLIENTSTATUS #{user2.name}\t4\n"
    
    # Adding start rectangles
    assert Enum.count(battle.start_rectangles) == 2
    _send(socket, "ADDSTARTRECT 2 50 50 100 100\n")
    _ = _recv(socket)

    battle = Battle.get_battle(battle_id)
    assert Enum.count(battle.start_rectangles) == 3

    _send(socket, "REMOVESTARTRECT 2\n")
    _ = _recv(socket)
    battle = Battle.get_battle(battle_id)
    assert Enum.count(battle.start_rectangles) == 2

    # Leave the battle
    
  end
end