defmodule ResistanceWeb.HomeLive do
  use ResistanceWeb, :live_view
  require Logger

  @impl true
  def mount(_params, session, socket) do
    init_state =
      socket
      |> assign(:self, session["_csrf_token"])
      |> assign(:muted, false)
      |> assign(:music_file, "home-music.mp3")

    {:ok, init_state}
  end

  @impl true
  def handle_event("create_room", _value, socket) do
    id = Ecto.UUID.generate |> String.slice(-6..-1)
    {:ok, _} = Avalon.Supervisor.start_pregame(id)
    Pregame.Server.add_player(id, socket.assigns.self, String.trim(NameGenerator.generate))
    {:noreply, push_navigate(socket, to: "/lobby/#{id}")}
  end

end
