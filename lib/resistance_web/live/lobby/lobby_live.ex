defmodule ResistanceWeb.LobbyLive do
  use ResistanceWeb, :live_view
  require Logger

  @impl true
  def mount(_params, session, socket) do
    init_state = socket
      |> assign(:self, session["_csrf_token"])
      |> assign(:players, %{})
      |> assign(:time_to_start, nil)
      |> assign(:timer_ref, nil)

    case Pregame.Server.is_player(session["_csrf_token"]) do
      false -> {:ok, init_state}
      true ->
        Pregame.Server.subscribe()
        {:ok, init_state |> assign(:players, Pregame.Server.get_players)}
    end
  end

  @impl true
  def handle_params(_params, _url, %{assigns: %{self: self} } = socket) do
    case Pregame.Server.is_player(self) do
      false -> {:noreply, push_navigate(socket, to: "/")}
      true -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:update, players}, %{assigns: %{self: self}} = socket) do
    case players[self] == nil do
      true -> {:noreply, push_navigate(socket, to: "/")}
      false ->
        :timer.cancel(socket.assigns.timer_ref)
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
  def handle_info(:tick, %{assigns: %{time_to_start: s}} = socket) do
    case s do
      nil -> {:noreply, socket}
      0 -> {:noreply, push_navigate(socket, to: "/game")}
      _ -> {:noreply, socket |> assign(:time_to_start, s - 1)}
    end
  end

  @impl true
  def handle_event("toggle_ready", _params,  %{assigns: %{self: self} } = socket) do
    Pregame.Server.toggle_ready(self)
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, %{assigns: %{self: self} }) do
    Pregame.Server.remove_player(self)
  end
end
