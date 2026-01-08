defmodule ResistanceWeb.TopBar do
  use Phoenix.Component
  import ResistanceWeb.CoreComponents
  import ResistanceWeb.CustomModals
  alias ResistanceWeb.TopBar.QuitButton
  alias ResistanceWeb.TopBar.SoundToggle

  @doc """
  Creates the top bar
  """

  attr :muted, :any, required: true, doc: "Whether the music is muted or not"
  attr :music_file, :any, required: true, doc: "The music file to play"
  attr :show_quit, :boolean, default: false
  attr :room_code, :string, default: nil, doc: "The room code"


  def top_bar(assigns) do
    ~H"""
    <div class="avalon-top-bar">
      <.how_to_play_shortcut />
      <.live_component module={SoundToggle} muted={@muted} music_file={@music_file} id="sound-toggle" />
      <%= if @show_quit do %>
        <QuitButton.quit_button />
      <% end %>
    </div>
    """
  end

  def how_to_play_shortcut(assigns) do
    ~H"""
    <button phx-click={show_modal("help_modal")} aria-label="how-to-play" class="cursor-pointer">
      <Heroicons.question_mark_circle solid class="h-5 w-5 stroke-current" />
    </button>
    <.help_modal />
    """
  end
end
