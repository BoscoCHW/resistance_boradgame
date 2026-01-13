defmodule ResistanceWeb.GameLive do
  use ResistanceWeb, :live_view
  require Logger

  @impl true
  def mount(_params, session, socket) do
    {:ok, socket
      |> assign(:token, session["_csrf_token"])
      |> assign(:room_code, nil)
      |> assign(:state, nil)
      |> assign(:form, to_form(%{"message" => ""}))
      |> assign(:form_key, 0)
      |> assign(:messages, [])
      |> assign(:time_remaining, nil)
      |> assign(:muted, false)
      |> assign(:music_file, "game-music.mp3")}
  end

  @impl true
  def handle_params(%{"room_code" => room_code}, _url, %{assigns: %{token: token} } = socket) do
    case Resistance.RoomCode.validate(room_code) do
      {:ok, normalized_code} ->
        cond do
          !Game.Server.room_exists?(normalized_code) || !Game.Server.is_player(normalized_code, token) ->
            {:noreply, push_navigate(socket, to: "/")}
          true ->
            Game.Server.subscribe(normalized_code)
            state = Game.Server.get_state(normalized_code)
            {:noreply, socket
              |> assign(:room_code, normalized_code)
              |> assign(:state, state)
              |> assign(:self, get_self(token, state.players))}
        end

      {:error, _} ->
        {:noreply, push_navigate(socket, to: "/")}
    end
  end

  @impl true
  def handle_info({:message, msg}, socket) do
    {:noreply, socket
      |> assign(:form, to_form(%{"message" => ""}))
      |> assign(:messages, [msg | socket.assigns.messages])}
  end

  @impl true
  def handle_info({:update, state}, socket) do
    Logger.log(:info, "[client] Stage: #{inspect state.stage}")

    if get_self(socket.assigns.self.id, state.players) == nil do
      {:noreply, push_navigate(socket, to: "/")}
    end

    {:noreply, socket
      |> assign(:state, state)
      |> assign(:self, get_self(socket.assigns.self.id, state.players))}
  end

  @impl true
  def handle_info({:time_update, %{time_remaining: seconds}}, socket) do
    {:noreply, assign(socket, :time_remaining, seconds)}
  end

  @impl true
  def handle_event("toggle_quest_member", %{"player" => player_id}, socket) do
    Game.Server.toggle_quest_member(socket.assigns.room_code, socket.assigns.self.id, player_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("vote_for_team", %{"vote" => vote}, socket) do
    Game.Server.vote_for_team(socket.assigns.room_code, socket.assigns.self.id, String.to_atom(vote))
    {:noreply, socket}
  end

  @impl true
  def handle_event("vote_for_quest", %{"vote" => vote}, socket) do
    Game.Server.vote_for_mission(socket.assigns.room_code, socket.assigns.self.id, String.to_atom(vote))
    {:noreply, socket}
  end

  @impl true
  def handle_event("message", %{"message" => msg}, socket) do
    if (String.trim(msg) != "") do
      Game.Server.message(socket.assigns.room_code, socket.assigns.self.id, msg)
    end
    # Increment form_key to force form reset
    {:noreply, socket
      |> assign(:form, to_form(%{"message" => ""}))
      |> assign(:form_key, socket.assigns.form_key + 1)}
  end

  @impl true
  def handle_event("quit", _params, socket) do
    room_code = socket.assigns.room_code
    player_id = socket.assigns.self.id

    # Player is in game, so remove from game server only
    # Pregame server is waiting for game to end, no need to remove
    if room_code do
      Game.Server.remove_player(room_code, player_id)
    end

    {:noreply, push_navigate(socket, to: "/")}
  end

  defp get_self(id, players) do
    Enum.find(players, fn p -> p.id == id end)
  end
end
