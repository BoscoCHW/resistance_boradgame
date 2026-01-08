defmodule ResistanceWeb.TopBar do
  use Phoenix.Component

  alias ResistanceWeb.TopBar.QuitButton
  alias ResistanceWeb.TopBar.SoundToggle
  alias ResistanceWeb.TopBar.HowToPlayShortcut

  @doc """
  Creates the top bar
  """

  attr :muted, :any, required: true, doc: "Whether the music is muted or not"
  attr :music_file, :any, required: true, doc: "The music file to play"
  attr :show_quit, :boolean, default: false
  attr :id, :string, default: "", doc: "the player's id"
  attr :room_code, :string, default: nil, doc: "the room code"

  def top_bar(assigns) do
    ~H"""
        <div class="avalon-top-bar">
          <.live_component module={HowToPlayShortcut} id="how-to-play-shortcut-button" />
          <.live_component module={SoundToggle} muted={@muted} music_file={@music_file} id="sound-toggle" />
          <%= if @show_quit do %>
            <.live_component module={QuitButton} id={@id} room_code={@room_code}/>
          <% end %>
        </div>
    """
  end
end
