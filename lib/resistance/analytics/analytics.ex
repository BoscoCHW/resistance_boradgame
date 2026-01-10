defmodule Resistance.Analytics do
  @moduledoc """
  The Analytics context - handles visitor statistics tracking.
  """

  import Ecto.Query, warn: false
  alias Resistance.Repo
  alias Resistance.Analytics.Stat

  @metric_names [
    "site_visits",
    "rooms_created",
    "games_started",
    "good_team_wins",
    "bad_team_wins"
  ]

  @doc """
  Increments a statistic counter by 1.
  This operation is async and fire-and-forget to avoid blocking game logic.
  """
  def increment_stat(metric_name) when metric_name in @metric_names do
    Task.Supervisor.start_child(
      Resistance.AnalyticsTaskSupervisor,
      fn -> do_increment_stat(metric_name) end
    )
    :ok
  end

  def increment_stat(_invalid_metric), do: {:error, :invalid_metric}

  # Internal function that performs the actual database increment.
  # Uses an atomic UPDATE to avoid race conditions.
  defp do_increment_stat(metric_name) do
    try do
      {1, _} =
        from(s in Stat, where: s.metric_name == ^metric_name)
        |> Repo.update_all(
          inc: [count: 1],
          set: [last_updated: DateTime.utc_now()]
        )

      # Broadcast the update to all connected dashboard clients
      broadcast_stat_update(metric_name)
      :ok
    rescue
      error ->
        require Logger
        Logger.error("Failed to increment stat #{metric_name}: #{inspect(error)}")
        :error
    end
  end

  @doc """
  Gets all statistics as a map.
  Returns: %{"site_visits" => 123, "rooms_created" => 45, ...}
  """
  def get_all_stats do
    stats = Repo.all(Stat)

    stats
    |> Enum.map(fn stat -> {stat.metric_name, stat.count} end)
    |> Map.new()
  end

  @doc """
  Gets a single statistic value.
  """
  def get_stat(metric_name) when metric_name in @metric_names do
    case Repo.get_by(Stat, metric_name: metric_name) do
      nil -> {:ok, 0}
      stat -> {:ok, stat.count}
    end
  end

  # Broadcasts statistic updates to Phoenix Channel subscribers.
  defp broadcast_stat_update(metric_name) do
    {:ok, count} = get_stat(metric_name)

    Phoenix.PubSub.broadcast(
      Resistance.PubSub,
      "analytics:stats",
      {:stat_updated, %{metric: metric_name, count: count}}
    )
  end

  @doc """
  Broadcasts all stats to a newly connected client.
  """
  def broadcast_all_stats do
    stats = get_all_stats()

    Phoenix.PubSub.broadcast(
      Resistance.PubSub,
      "analytics:stats",
      {:all_stats, stats}
    )
  end
end
