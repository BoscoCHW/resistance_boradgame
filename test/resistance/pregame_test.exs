defmodule Pregame.ServerTest do
  use ExUnit.Case, async: false

  alias Pregame.Server

  setup do
    {:ok, pid} = Server.start_link("room1")
    on_exit(fn ->
      # Ensure cleanup
      try do
        GenServer.stop(pid)
      catch
        :exit, _ -> :ok
      end
    end)
    {:ok, %{pid: pid}}
  end

  test "add_player/3 adds a player to the pregame lobby" do
    assert :ok == Server.add_player("room1", 1, "Alice")
    assert %{1 => {"Alice", false}} == Server.get_players("room1")
  end

  test "is_player/2 returns true if the player is in the pregame lobby" do
    Server.add_player("room1", 1, "Alice")
    assert true == Server.is_player("room1", 1)
    assert false == Server.is_player("room1", 2)
  end

  test "get_players/1 returns a map of player ids to {name, ready} tuples" do
    Server.add_player("room1", 1, "Alice")
    Server.add_player("room1", 2, "Bobby")
    assert %{1 => {"Alice", false}, 2 => {"Bobby", false}} == Server.get_players("room1")
  end

  test "remove_player/2 removes a player from the pregame lobby" do
    Server.add_player("room1", 1, "Alice")
    Server.add_player("room1", 2, "Bobby")
    Server.remove_player("room1", 1)
    assert %{2 => {"Bobby", false}} == Server.get_players("room1")
  end

  test "toggle_ready/2 toggles a player's ready status" do
    Server.add_player("room1", 1, "Alice")
    Server.toggle_ready("room1", 1)
    assert %{1 => {"Alice", true}} == Server.get_players("room1")
  end

  test "validate_name/2 returns :ok if the name is valid, or {:error, reason} if the name is invalid" do
    assert :ok == Server.validate_name("room1", "Alice")
    Server.add_player("room1", 1, "Alice")
    assert {:error, "Name is already taken."} == Server.validate_name("room1", "Alice")
  end
end