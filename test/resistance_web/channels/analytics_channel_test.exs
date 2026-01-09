defmodule ResistanceWeb.AnalyticsChannelTest do
  use ResistanceWeb.ChannelCase, async: false

  setup do
    {:ok, _, socket} =
      ResistanceWeb.UserSocket
      |> socket("user_id", %{})
      |> subscribe_and_join(ResistanceWeb.AnalyticsChannel, "analytics:stats")

    %{socket: socket}
  end

  test "broadcasts all stats upon joining" do
    assert_push "all_stats", %{
      "site_visits" => _
    }
  end

  test "handles get_stats request", %{socket: socket} do
    ref = push(socket, "get_stats", %{})
    assert_reply ref, :ok, %{}
  end
end
