defmodule ResistanceWeb.LobbyLive do
  use ResistanceWeb, :live_view
  require Logger

  @impl true
  def mount(_params, session, socket) do
    init_state = socket
      |> assign(:self, session["_csrf_token"])
      |> assign(:room_code, nil)
      |> assign(:players, %{})
      |> assign(:time_to_start, nil)
      |> assign(:timer_ref, nil)
      |> assign(:muted, false)
      |> assign(:music_file, "lobby-music.mp3")
    {:ok, init_state}
  end

  @impl true
  def handle_params(%{"room_code" => room_code}, _url, %{assigns: %{self: self} } = socket) do
    case Resistance.RoomCode.validate(room_code) do
      {:ok, normalized_code} ->
        cond do
          Game.Server.room_exists?(normalized_code) && Game.Server.is_player(normalized_code, self) ->
            {:noreply, push_navigate(socket, to: "/game/#{normalized_code}")}
          !Pregame.Server.is_player(normalized_code, self) ->
            {:noreply, push_navigate(socket, to: "/")}
          true ->
            Pregame.Server.subscribe(normalized_code)
            {:noreply, socket
              |> assign(:room_code, normalized_code)
              |> assign(:players, Pregame.Server.get_players(normalized_code))}
        end

      {:error, _} ->
        {:noreply, push_navigate(socket, to: "/")}
    end
  end

  @impl true
  def handle_info({:update, players}, %{assigns: %{self: self}} = socket) do
    case players[self] == nil do
      true -> {:noreply, push_navigate(socket, to: "/")}
      false ->
        if socket.assigns.timer_ref, do: :timer.cancel(socket.assigns.timer_ref)
        {:noreply, socket
          |> assign(:players, players)
          |> assign(:time_to_start, nil)
          |> assign(:timer_ref, nil)}
    end
  end

  @impl true
  def handle_info({:start_timer, players}, socket) do
    {:ok, timer_ref} = :timer.send_interval(1000, self(), :tick)
    {:noreply, socket
      |> assign(:players, players)
      |> assign(:time_to_start, 5)
      |> assign(:timer_ref, timer_ref)}
  end

  @impl true
  def handle_info(:tick, %{assigns: %{time_to_start: s, room_code: room_code}} = socket) do
    case s do
      nil -> {:noreply, socket}
      0 -> {:noreply, push_navigate(socket, to: "/game/#{room_code}")}
      _ -> {:noreply, socket |> assign(:time_to_start, s - 1)}
    end
  end

  @impl true
  def handle_info({:error, _msg}, socket) do
    # Game failed to start, reset the countdown
    if socket.assigns.timer_ref, do: :timer.cancel(socket.assigns.timer_ref)
    {:noreply, socket
      |> assign(:time_to_start, nil)
      |> assign(:timer_ref, nil)
      |> put_flash(:error, "Failed to start game. Please try again.")}
  end

  @impl true
  def handle_event("toggle_ready", _params,  %{assigns: %{self: self, room_code: room_code} } = socket) do
    Pregame.Server.toggle_ready(room_code, self)
    {:noreply, socket}
  end

  @impl true
  def handle_event("exit_lobby", _params, %{assigns: %{self: self, room_code: room_code} } = socket) do
    Pregame.Server.remove_player(room_code, self)
    {:noreply, push_navigate(socket, to: "/")}
  end

  @impl true
  def handle_event("quit", _params, %{assigns: %{self: self, room_code: room_code} } = socket) do
    # Player is in lobby, so remove from pregame server only
    if room_code do
      Pregame.Server.remove_player(room_code, self)
    end
    {:noreply, push_navigate(socket, to: "/")}
  end

  @impl true
  def terminate(_reason, %{assigns: %{self: self, room_code: room_code} }) do
    if room_code do
      Pregame.Server.remove_player(room_code, self)
    end
  end
end
