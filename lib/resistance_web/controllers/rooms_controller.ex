defmodule ResistanceWeb.RoomsController do
  use ResistanceWeb, :controller

  @doc """
  GET /api/rooms
  Returns list of all active pregame and game rooms with status information.
  """
  def index(conn, _params) do
    rooms = get_all_active_rooms()

    json(conn, %{
      data: rooms,
      timestamp: DateTime.utc_now(),
      total_count: length(rooms)
    })
  end

  # Query Registry for all pregame rooms
  defp get_pregame_rooms do
    Registry.select(Resistance.RoomRegistry, [
      {{{:pregame, :"$1"}, :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}
    ])
    |> Enum.map(fn {room_code, _pid} ->
      format_pregame_room(room_code)
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Query Registry for all game rooms
  defp get_game_rooms do
    Registry.select(Resistance.RoomRegistry, [
      {{{:game, :"$1"}, :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}
    ])
    |> Enum.map(fn {room_code, _pid} ->
      format_game_room(room_code)
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Format pregame room data
  defp format_pregame_room(room_code) do
    try do
      players = Pregame.Server.get_players(room_code)
      player_count = map_size(players)
      ready_count = Enum.count(players, fn {_id, {_name, ready}} -> ready end)

      %{
        room_code: room_code,
        type: "pregame",
        player_count: player_count,
        max_players: 5,
        ready_count: ready_count,
        status: format_pregame_status(player_count, ready_count)
      }
    rescue
      _ -> nil
    end
  end

  # Format game room data
  defp format_game_room(room_code) do
    try do
      state = Game.Server.get_state(room_code)

      if state do
        %{
          room_code: room_code,
          type: "game",
          player_count: length(state.players),
          max_players: 5,
          round: length(state.quest_outcomes) + 1,
          stage: state.stage,
          status: format_game_status(state)
        }
      else
        nil
      end
    rescue
      _ -> nil
    end
  end

  # Format pregame status text
  defp format_pregame_status(player_count, ready_count) do
    "#{ready_count}/#{player_count} ready (need #{5 - player_count} more players)"
  end

  # Format game status text
  defp format_game_status(state) do
    round = length(state.quest_outcomes) + 1
    stage_text = format_stage(state.stage)
    "Round #{round}: #{stage_text}"
  end

  # Convert stage atoms to readable text
  defp format_stage(:init), do: "Initializing"
  defp format_stage(:party_assembling), do: "Party Assembling"
  defp format_stage(:voting), do: "Team Voting"
  defp format_stage(:quest), do: "On Quest"
  defp format_stage(:quest_reveal), do: "Quest Results"
  defp format_stage(:end_game), do: "Game Ended"

  # Combine all rooms
  defp get_all_active_rooms do
    pregame = get_pregame_rooms()
    games = get_game_rooms()
    pregame ++ games
  end
end
