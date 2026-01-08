defmodule ResistanceWeb.TopBar.QuitButton do
  use Phoenix.Component
  import ResistanceWeb.CoreComponents

  @doc """
  Renders a quit button with confirmation modal.
  The parent LiveView must implement a "quit" event handler.
  """
  def quit_button(assigns) do
    ~H"""
      <div>
        <.modal id="quit-button" class="quit-modal">
          <:title>
              Quit
          </:title>

          <p>Are you sure you want to leave?</p>

          <:confirm>
            <span phx-click="quit">
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
end
