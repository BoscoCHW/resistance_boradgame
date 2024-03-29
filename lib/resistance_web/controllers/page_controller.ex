defmodule ResistanceWeb.PageController do
  use ResistanceWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end

  def not_found(conn, _params) do
    render(conn, "not_found.html", assigns: %{})
  end
end
