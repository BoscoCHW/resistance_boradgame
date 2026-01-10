defmodule ResistanceWeb.AnalyticsControllerTest do
  use ResistanceWeb.ConnCase, async: false

  describe "GET /api/analytics/stats" do
    test "returns all statistics as JSON", %{conn: conn} do
      conn = get(conn, ~p"/api/analytics/stats")

      assert %{
        "data" => %{
          "site_visits" => _,
          "rooms_created" => _,
          "games_started" => _,
          "good_team_wins" => _,
          "bad_team_wins" => _
        }
      } = json_response(conn, 200)
    end
  end
end
