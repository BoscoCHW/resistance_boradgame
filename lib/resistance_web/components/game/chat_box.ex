defmodule ResistanceWeb.Game.ChatBox do
  use Phoenix.Component

  import ResistanceWeb.CoreComponents

  @doc """
  Creates a chat box for use in the Game LiveView
  """

  attr :form, :any, required: true, doc: "Form containing messages input"
  attr :form_key, :integer, required: true, doc: "Unique key to force form reset"
  attr :messages, :any, required: true, doc: "Message list"

  def chat_box(assigns) do
    ~H"""
      <div class="avalon-chat-box">
        <div class="messages">
          <%= Enum.map(@messages, fn {from, msg} -> %>
            <p class={"#{to_string(from)}-msg"}> <%= msg %> </p>
          <% end) %>
        </div>

        <.simple_form
          id={"message-form-#{@form_key}"}
          for={@form}
          phx-submit="message"
        >
            <.input
                field={@form[:message]}
                placeholder="Send a missive..."/>
            <input id="message-submit" type="submit" hidden />
        </.simple_form>
      </div>
    """
  end
end
