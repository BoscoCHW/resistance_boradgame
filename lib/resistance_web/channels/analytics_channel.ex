defmodule ResistanceWeb.AnalyticsChannel do
  use ResistanceWeb, :channel
  alias Resistance.Analytics

  @impl true
  def join("analytics:stats", _payload, socket) do
    # Send initial stats to the client
    send(self(), :after_join)
    {:ok, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    stats = Analytics.get_all_stats()
    push(socket, "all_stats", stats)
    {:noreply, socket}
  end

  @impl true
  def handle_in("get_stats", _payload, socket) do
    stats = Analytics.get_all_stats()
    {:reply, {:ok, stats}, socket}
  end
end
