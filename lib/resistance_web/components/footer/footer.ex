defmodule ResistanceWeb.Footer do
  use Phoenix.Component

  @doc """
  Creates the footer
  """

  def footer(assigns) do
    ~H"""
        <div class="avalon-footer">
          <p class="dimmed"> &#169 2022 All Rights Reserved</p>
        </div>
    """
  end
end
