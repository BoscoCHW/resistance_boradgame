defmodule ResistanceWeb.AnalyticsController do
  use ResistanceWeb, :controller

  @doc """
  GET /api/analytics/stats
  Returns all statistics as JSON.
  """
  def stats(conn, _params) do
    stats = Resistance.Analytics.get_all_stats()

    json(conn, %{
      data: stats,
      timestamp: DateTime.utc_now()
    })
  end

  @doc """
  GET /api/analytics/health
  Health check endpoint for monitoring.
  """
  def health(conn, _params) do
    json(conn, %{status: "ok", service: "analytics"})
  end
end
