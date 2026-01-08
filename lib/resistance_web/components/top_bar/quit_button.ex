defmodule ResistanceWeb.TopBar.QuitButton do
  use Phoenix.LiveComponent
  import ResistanceWeb.CoreComponents

  def render(assigns) do
    ~H"""
      <div>
        <.modal id="quit-button" class="quit-modal">
          <:title>
              Quit
          </:title>

          <p>Are you sure you want to leave?</p>

          <:confirm>
            <span phx-click="quit" phx-value-id={@id} phx-target={@myself}>
            Confirm
            </span>
          </:confirm>
        </.modal>

        <Heroicons.arrow_right_on_rectangle
          class="w-5 h-5 cursor-pointer"
          phx-click={show_modal("quit-button")}
        />
      </div>
    """
  end

  def handle_event("quit", %{"id" => id}, socket) do
    room_code = socket.assigns.room_code

    if room_code do
      Pregame.Server.remove_player(room_code, id)
      if Game.Server.room_exists?(room_code) do
        Game.Server.remove_player(room_code, id)
      end
    end

    {:noreply, push_navigate(socket, to: "/")}
  end
end
