defmodule Resistance.AnalyticsTest do
  use Resistance.DataCase, async: false

  alias Resistance.Analytics
  import Ecto.Query

  setup do
    # Reset all stats to 0 before each test
    Analytics.get_all_stats()
    |> Enum.each(fn {metric, _} ->
      from(s in Resistance.Analytics.Stat, where: s.metric_name == ^metric)
      |> Resistance.Repo.update_all(set: [count: 0])
    end)

    :ok
  end

  describe "increment_stat/1" do
    test "increments site visits" do
      assert :ok = Analytics.increment_stat("site_visits")

      # Wait for async task
      Process.sleep(100)

      {:ok, count} = Analytics.get_stat("site_visits")
      assert count == 1
    end

    test "returns error for invalid metric" do
      assert {:error, :invalid_metric} = Analytics.increment_stat("invalid")
    end
  end
end
