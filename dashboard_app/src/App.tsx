import React from 'react';
import { useAnalytics } from './hooks/useAnalytics';
import { useAnalyticsStore } from './store/analyticsStore';
import { StatCard } from './components/StatCard';

function App() {
  useAnalytics(); // Connect to Phoenix Channel

  const stats = useAnalyticsStore((state) => state.stats);
  const connected = useAnalyticsStore((state) => state.connected);

  const totalGames = stats.good_team_wins + stats.bad_team_wins;
  const goodWinRate = totalGames > 0
    ? ((stats.good_team_wins / totalGames) * 100).toFixed(1)
    : 0;

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100">
      <div className="container mx-auto px-4 py-8">
        {/* Header */}
        <div className="text-center mb-12">
          <h1 className="text-5xl font-bold text-gray-800 mb-2">
            Avalon Analytics Dashboard
          </h1>
          <p className="text-gray-600">Real-time visitor statistics</p>
          <div className="mt-4">
            <span
              className={`inline-flex items-center px-3 py-1 rounded-full text-sm font-medium ${
                connected
                  ? 'bg-green-100 text-green-800'
                  : 'bg-red-100 text-red-800'
              }`}
            >
              <span
                className={`w-2 h-2 mr-2 rounded-full ${
                  connected ? 'bg-green-500' : 'bg-red-500'
                }`}
              />
              {connected ? 'Connected' : 'Disconnected'}
            </span>
          </div>
        </div>

        {/* Stats Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-8">
          <StatCard
            label="Site Visits"
            value={stats.site_visits}
            icon="👥"
            color="border-blue-500"
          />
          <StatCard
            label="Rooms Created"
            value={stats.rooms_created}
            icon="🚪"
            color="border-purple-500"
          />
          <StatCard
            label="Games Started"
            value={stats.games_started}
            icon="🎮"
            color="border-green-500"
          />
          <StatCard
            label="Good Team Wins"
            value={stats.good_team_wins}
            icon="⚔️"
            color="border-yellow-500"
          />
          <StatCard
            label="Bad Team Wins"
            value={stats.bad_team_wins}
            icon="🗡️"
            color="border-red-500"
          />
          <StatCard
            label="Good Win Rate"
            value={parseFloat(goodWinRate.toString())}
            icon="📊"
            color="border-indigo-500"
          />
        </div>

        {/* Footer */}
        <div className="text-center text-gray-500 text-sm">
          <p>Updates in real-time via WebSocket</p>
        </div>
      </div>
    </div>
  );
}

export default App;
