defmodule ResistanceWeb.PageControllerTest do
  use ResistanceWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Avalon"
  end
end