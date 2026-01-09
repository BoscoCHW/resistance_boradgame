# Implementation Plan: Visitor Statistics Tracking with React Dashboard

## Overview
Add visitor statistics tracking to the Phoenix LiveView Resistance game and create a separate React dashboard that displays real-time statistics via WebSocket (Phoenix Channels).

## Requirements
1. **Track 5 statistics** (all page loads, not unique visitors):
   - Site visits (home page loads)
   - Rooms created
   - Games started
   - Good team wins
   - Bad team wins

2. **React Dashboard**:
   - Public access (no authentication)
   - Real-time updates via Phoenix Channels (WebSocket)
   - Separate deployment from Phoenix backend
   - Location: `dashboard_app/` in project root

3. **API Backend**:
   - Phoenix serves JSON API and WebSocket
   - CORS enabled for separate React deployment
   - Non-blocking analytics (never slow down game)

## Architecture

### Database Layer
- Single table `analytics_stats` with metric names
- Atomic increment operations to prevent race conditions
- Initial values: 0 for all metrics

### Event Tracking
- Async fire-and-forget using `Task.Supervisor`
- Hook into existing game flow at 5 key points
- No impact on game performance if analytics fail

### Real-time Updates
- Phoenix Channels for WebSocket communication
- PubSub broadcasts on every stat increment
- React dashboard subscribes to `analytics:stats` channel

---

## Phase 1: Database Schema and Context

### 1.1 Create Migration

**File**: `priv/repo/migrations/YYYYMMDDHHMMSS_create_analytics_stats.exs`

```elixir
defmodule Resistance.Repo.Migrations.CreateAnalyticsStats do
  use Ecto.Migration

  def change do
    create table(:analytics_stats, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :metric_name, :string, null: false
      add :count, :bigint, null: false, default: 0
      add :last_updated, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:analytics_stats, [:metric_name])

    # Initialize the five metrics
    execute """
      INSERT INTO analytics_stats (id, metric_name, count, last_updated, inserted_at, updated_at)
      VALUES
        (gen_random_uuid(), 'site_visits', 0, NOW(), NOW(), NOW()),
        (gen_random_uuid(), 'rooms_created', 0, NOW(), NOW(), NOW()),
        (gen_random_uuid(), 'games_started', 0, NOW(), NOW(), NOW()),
        (gen_random_uuid(), 'good_team_wins', 0, NOW(), NOW(), NOW()),
        (gen_random_uuid(), 'bad_team_wins', 0, NOW(), NOW(), NOW())
    """, """
      DELETE FROM analytics_stats WHERE metric_name IN (
        'site_visits', 'rooms_created', 'games_started', 'good_team_wins', 'bad_team_wins'
      )
    """
  end
end
```

**Run**: `mix ecto.gen.migration create_analytics_stats` then add above code, then `mix ecto.migrate`

---

### 1.2 Create Ecto Schema

**File**: `lib/resistance/analytics/stat.ex`

```elixir
defmodule Resistance.Analytics.Stat do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "analytics_stats" do
    field :metric_name, :string
    field :count, :integer
    field :last_updated, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(stat, attrs) do
    stat
    |> cast(attrs, [:metric_name, :count, :last_updated])
    |> validate_required([:metric_name, :count, :last_updated])
    |> unique_constraint(:metric_name)
  end
end
```

---

### 1.3 Create Analytics Context

**File**: `lib/resistance/analytics/analytics.ex`

```elixir
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

  @doc """
  Internal function that performs the actual database increment.
  Uses an atomic UPDATE to avoid race conditions.
  """
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

  @doc """
  Broadcasts statistic updates to Phoenix Channel subscribers.
  """
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
```

---

### 1.4 Add Task Supervisor to Application

**File**: `lib/resistance/application.ex`

**Add after line 22** (after `Resistance.RoomSupervisor`):

```elixir
# Task supervisor for async analytics tracking
{Task.Supervisor, name: Resistance.AnalyticsTaskSupervisor},
```

---

## Phase 2: Event Tracking Instrumentation

### 2.1 Track Site Visits

**File**: `lib/resistance_web/live/home/home_live.ex`

**Modify lines 5-17** in the `mount/3` function:

```elixir
@impl true
def mount(_params, session, socket) do
  # Track site visit (async, non-blocking)
  Resistance.Analytics.increment_stat("site_visits")

  init_state =
    socket
    |> assign(:self, session["_csrf_token"])
    |> assign(:form, to_form(%{"name" => "", "room_code" => ""}))
    |> assign(:is_creating, false)
    |> assign(:is_full, false)
    |> assign(:muted, false)
    |> assign(:music_file, "home-music.mp3")

  {:ok, init_state}
end
```

---

### 2.2 Track Room Created

**File**: `lib/resistance/pregame.ex`

**Modify lines 45-52** in `find_or_create/1`:

```elixir
def find_or_create(room_code) do
  case find(room_code) do
    {:ok, pid} ->
      {:ok, pid}

    :error ->
      case DynamicSupervisor.start_child(
             Resistance.RoomSupervisor,
             {__MODULE__, room_code}
           ) do
        {:ok, pid} ->
          # Track room creation only when a NEW room is created
          Resistance.Analytics.increment_stat("rooms_created")
          {:ok, pid}
        {:error, {:already_started, pid}} ->
          {:ok, pid}
        error ->
          error
      end
  end
end
```

---

### 2.3 Track Game Started

**File**: `lib/resistance/pregame.ex`

**Modify lines 301-306** in `handle_info(:start_game)`:

```elixir
if all_ready do
  case Game.Server.start_link(state.room_code, state.players) do
    {:ok, _pid} ->
      # Track game start only when game successfully launches
      Resistance.Analytics.increment_stat("games_started")
      :ok
    {:error, reason} ->
      Logger.error("Failed to start game: #{inspect(reason)}")
      broadcast(state.room_code, :error, "Failed to start game")
  end
end
```

---

### 2.4 Track Good Team Wins

**File**: `lib/resistance/game.ex`

**Location 1 - Line 454-457** in `clean_up(%{stage: :quest_reveal})`:

```elixir
{:end_game, :good} ->
  Resistance.Analytics.increment_stat("good_team_wins")
  broadcast(state.room_code, :message, {:server, "Arthur wins!"})
  broadcast(state.room_code, :update, %{state | stage: :end_game, winning_team: :good})
  end_game(state.room_code)
```

**Location 2 - Line 286-290** in `handle_cast({:remove_player})`:

```elixir
num_bad_guys == 0 ->
  Resistance.Analytics.increment_stat("good_team_wins")
  %{new_state | stage: :end_game, winning_team: :good}
  broadcast(state.room_code, :message, "Arthur wins!")
  broadcast(state.room_code, :update, new_state)
  end_game(state.room_code)
```

---

### 2.5 Track Bad Team Wins

**File**: `lib/resistance/game.ex`

**Location 1 - Line 421-424** in `clean_up(%{stage: :voting})`:

```elixir
if state.team_rejection_count >= 4 do
  Resistance.Analytics.increment_stat("bad_team_wins")
  broadcast(state.room_code, :message, {:server, "Bad guys win!"})
  broadcast(state.room_code, :update, %{state | stage: :end_game, winning_team: :bad})
  end_game(state.room_code)
```

**Location 2 - Line 449-452** in `clean_up(%{stage: :quest_reveal})`:

```elixir
{:end_game, :bad} ->
  Resistance.Analytics.increment_stat("bad_team_wins")
  broadcast(state.room_code, :message, {:server, "Mordred wins!"})
  broadcast(state.room_code, :update, %{state | stage: :end_game, winning_team: :bad})
  end_game(state.room_code)
```

**Location 3 - Line 280-284** in `handle_cast({:remove_player})`:

```elixir
num_bad_guys > num_good_guys ->
  Resistance.Analytics.increment_stat("bad_team_wins")
  %{new_state | stage: :end_game, winning_team: :bad}
  broadcast(state.room_code, :error, "Mordred wins!")
  broadcast(state.room_code, :update, new_state)
  end_game(state.room_code)
```

---

## Phase 3: API Layer (Phoenix Backend)

### 3.1 Add CORS Dependency

**File**: `mix.exs`

**Add after line 52** (after `{:plug_cowboy, "~> 2.5"}`):

```elixir
{:cors_plug, "~> 3.0"}
```

**Run**: `mix deps.get`

---

### 3.2 Configure CORS

**File**: `lib/resistance_web/endpoint.ex`

**Add after line 41** (after the JSON parser plug):

```elixir
# CORS configuration for separate React dashboard deployment
plug CORSPlug,
  origin: [
    ~r/^https?:\/\/localhost:\d+$/,  # Development (any port)
    ~r/^https:\/\/.*\.vercel\.app$/,  # Vercel deployments
    ~r/^https:\/\/.*\.netlify\.app$/  # Netlify deployments
    # Add your production dashboard domain here
  ],
  methods: ["GET", "OPTIONS"],
  headers: ["Content-Type", "Authorization"]
```

---

### 3.3 Create Analytics Controller

**File**: `lib/resistance_web/controllers/analytics_controller.ex`

```elixir
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
```

---

### 3.4 Create Phoenix Channel

**File**: `lib/resistance_web/channels/analytics_channel.ex`

```elixir
defmodule ResistanceWeb.AnalyticsChannel do
  use Phoenix.Channel
  require Logger

  @doc """
  Join the analytics channel - no authentication required (public stats).
  """
  def join("analytics:stats", _payload, socket) do
    # Send current stats immediately upon connection
    send(self(), :after_join)
    {:ok, socket}
  end

  @doc """
  After joining, send all current statistics to the client.
  """
  def handle_info(:after_join, socket) do
    stats = Resistance.Analytics.get_all_stats()
    push(socket, "all_stats", stats)
    {:noreply, socket}
  end

  @doc """
  Clients can request a stats refresh.
  """
  def handle_in("get_stats", _payload, socket) do
    stats = Resistance.Analytics.get_all_stats()
    {:reply, {:ok, stats}, socket}
  end
end
```

---

### 3.5 Create User Socket

**File**: `lib/resistance_web/channels/user_socket.ex`

```elixir
defmodule ResistanceWeb.UserSocket do
  use Phoenix.Socket

  # Channels
  channel "analytics:*", ResistanceWeb.AnalyticsChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    # No authentication needed for public analytics
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
```

---

### 3.6 Update Endpoint for WebSocket

**File**: `lib/resistance_web/endpoint.ex`

**Add after line 14** (after LiveView socket):

```elixir
socket "/socket", ResistanceWeb.UserSocket,
  websocket: true,
  longpoll: false
```

---

### 3.7 Update Router

**File**: `lib/resistance_web/router.ex`

**Add after line 15** (after `:api` pipeline definition):

```elixir
scope "/api", ResistanceWeb do
  pipe_through :api

  get "/analytics/stats", AnalyticsController, :stats
  get "/analytics/health", AnalyticsController, :health
end
```

---

## Phase 4: React Dashboard

### 4.1 Initialize React Project

**Commands**:

```bash
cd /Users/bosco/Documents/github_proj/resistance_boradgame
mkdir dashboard_app
cd dashboard_app

# Initialize Vite + React + TypeScript
npm create vite@latest . -- --template react-ts

# Install dependencies
npm install phoenix zustand

# Install dev dependencies
npm install -D tailwindcss postcss autoprefixer
npx tailwindcss init -p
```

---

### 4.2 Configure Tailwind CSS

**File**: `dashboard_app/tailwind.config.js`

```javascript
/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
```

**File**: `dashboard_app/src/index.css`

```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```

---

### 4.3 Create Phoenix Channel Service

**File**: `dashboard_app/src/services/phoenixChannel.ts`

```typescript
import { Socket, Channel } from 'phoenix';

const SOCKET_URL = import.meta.env.VITE_PHOENIX_WS_URL || 'ws://localhost:4000/socket';

export interface AnalyticsStats {
  site_visits: number;
  rooms_created: number;
  games_started: number;
  good_team_wins: number;
  bad_team_wins: number;
}

export class AnalyticsChannel {
  private socket: Socket;
  private channel: Channel | null = null;
  private onStatsUpdate: ((stats: Partial<AnalyticsStats>) => void) | null = null;

  constructor() {
    this.socket = new Socket(SOCKET_URL, {
      params: {},
      reconnectAfterMs: (tries) => [1000, 2000, 5000, 10000][tries - 1] || 10000,
    });
  }

  connect(callback: (stats: Partial<AnalyticsStats>) => void) {
    this.onStatsUpdate = callback;
    this.socket.connect();

    this.channel = this.socket.channel('analytics:stats', {});

    this.channel.on('all_stats', (stats: AnalyticsStats) => {
      console.log('Received all stats:', stats);
      this.onStatsUpdate?.(stats);
    });

    this.channel.on('stat_updated', ({ metric, count }: { metric: string; count: number }) => {
      console.log('Stat updated:', metric, count);
      this.onStatsUpdate?.({ [metric]: count });
    });

    this.channel
      .join()
      .receive('ok', () => console.log('Joined analytics channel'))
      .receive('error', (err) => console.error('Failed to join channel:', err));

    return () => this.disconnect();
  }

  disconnect() {
    this.channel?.leave();
    this.socket.disconnect();
  }

  requestStats() {
    this.channel?.push('get_stats', {})
      .receive('ok', (stats) => this.onStatsUpdate?.(stats))
      .receive('error', (err) => console.error('Failed to get stats:', err));
  }
}
```

---

### 4.4 Create Zustand Store

**File**: `dashboard_app/src/store/analyticsStore.ts`

```typescript
import { create } from 'zustand';
import { AnalyticsStats } from '../services/phoenixChannel';

interface AnalyticsStore {
  stats: AnalyticsStats;
  connected: boolean;
  updateStats: (newStats: Partial<AnalyticsStats>) => void;
  setConnected: (connected: boolean) => void;
}

export const useAnalyticsStore = create<AnalyticsStore>((set) => ({
  stats: {
    site_visits: 0,
    rooms_created: 0,
    games_started: 0,
    good_team_wins: 0,
    bad_team_wins: 0,
  },
  connected: false,
  updateStats: (newStats) =>
    set((state) => ({
      stats: { ...state.stats, ...newStats },
    })),
  setConnected: (connected) => set({ connected }),
}));
```

---

### 4.5 Create Analytics Hook

**File**: `dashboard_app/src/hooks/useAnalytics.ts`

```typescript
import { useEffect } from 'react';
import { AnalyticsChannel } from '../services/phoenixChannel';
import { useAnalyticsStore } from '../store/analyticsStore';

export function useAnalytics() {
  const updateStats = useAnalyticsStore((state) => state.updateStats);
  const setConnected = useAnalyticsStore((state) => state.setConnected);

  useEffect(() => {
    const channel = new AnalyticsChannel();

    const disconnect = channel.connect((stats) => {
      updateStats(stats);
      setConnected(true);
    });

    return () => {
      setConnected(false);
      disconnect();
    };
  }, [updateStats, setConnected]);
}
```

---

### 4.6 Create StatCard Component

**File**: `dashboard_app/src/components/StatCard.tsx`

```typescript
import React from 'react';

interface StatCardProps {
  label: string;
  value: number;
  icon: string;
  color: string;
}

export const StatCard: React.FC<StatCardProps> = ({ label, value, icon, color }) => {
  return (
    <div className={`bg-white rounded-lg shadow-lg p-6 border-l-4 ${color}`}>
      <div className="flex items-center justify-between">
        <div>
          <p className="text-gray-500 text-sm uppercase tracking-wide">{label}</p>
          <p className="text-4xl font-bold text-gray-800 mt-2">
            {value.toLocaleString()}
          </p>
        </div>
        <div className="text-5xl">{icon}</div>
      </div>
    </div>
  );
};
```

---

### 4.7 Create Main App Component

**File**: `dashboard_app/src/App.tsx`

```typescript
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
```

---

### 4.8 Create Environment Files

**File**: `dashboard_app/.env.development`

```env
VITE_PHOENIX_WS_URL=ws://localhost:4000/socket
VITE_PHOENIX_HTTP_URL=http://localhost:4000/api
```

**File**: `dashboard_app/.env.production`

```env
VITE_PHOENIX_WS_URL=wss://your-phoenix-app.com/socket
VITE_PHOENIX_HTTP_URL=https://your-phoenix-app.com/api
```

---

### 4.9 Update Package.json Scripts

**File**: `dashboard_app/package.json`

Add to `"scripts"`:

```json
{
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview"
  }
}
```

---

## Phase 5: Testing

### 5.1 Test Analytics Context

**File**: `test/resistance/analytics/analytics_test.exs`

```elixir
defmodule Resistance.AnalyticsTest do
  use Resistance.DataCase, async: false

  alias Resistance.Analytics

  setup do
    # Reset all stats to 0 before each test
    Analytics.get_all_stats()
    |> Enum.each(fn {metric, _} ->
      from(s in Analytics.Stat, where: s.metric_name == ^metric)
      |> Repo.update_all(set: [count: 0])
    end)

    :ok
  end

  describe "increment_stat/1" do
    test "increments site visits" do
      assert :ok = Analytics.increment_stat("site_visits")

      Process.sleep(100)

      {:ok, count} = Analytics.get_stat("site_visits")
      assert count == 1
    end

    test "returns error for invalid metric" do
      assert {:error, :invalid_metric} = Analytics.increment_stat("invalid")
    end
  end
end
```

---

### 5.2 Test API Controller

**File**: `test/resistance_web/controllers/analytics_controller_test.exs`

```elixir
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
```

---

### 5.3 Test Phoenix Channel

**File**: `test/resistance_web/channels/analytics_channel_test.exs`

```elixir
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
```

---

## Verification Steps

### Backend Verification

1. **Database**:
   ```bash
   mix ecto.migrate
   psql -d resistance_dev -c "SELECT * FROM analytics_stats;"
   ```
   Should show 5 rows with count = 0

2. **API Endpoint**:
   ```bash
   curl http://localhost:4000/api/analytics/stats
   ```
   Should return JSON with all 5 stats

3. **WebSocket Connection** (browser console):
   ```javascript
   import { Socket } from "phoenix"
   const socket = new Socket('ws://localhost:4000/socket')
   socket.connect()
   const channel = socket.channel('analytics:stats')
   channel.join()
   channel.on('all_stats', stats => console.log(stats))
   ```

4. **Event Tracking**:
   - Visit home page → check `site_visits` incremented
   - Create room → check `rooms_created` incremented
   - Start game → check `games_started` incremented
   - Complete game → check win stats incremented

### Frontend Verification

1. **Start Phoenix**: `mix phx.server` (port 4000)
2. **Start React**: `cd dashboard_app && npm run dev` (port 5173)
3. **Open**: http://localhost:5173
4. **Check**:
   - Connection status shows "Connected"
   - All stats display current values
   - Stats update in real-time when backend events occur

---

## Deployment

### Phoenix Backend

1. Ensure `DATABASE_URL` environment variable is set
2. Run migrations: `mix ecto.migrate`
3. Set `CORS_ORIGINS` environment variable: `https://your-dashboard.vercel.app`
4. Deploy normally

### React Dashboard (Vercel)

1. Create `vercel.json`:
   ```json
   {
     "env": {
       "VITE_PHOENIX_WS_URL": "wss://your-backend.com/socket",
       "VITE_PHOENIX_HTTP_URL": "https://your-backend.com/api"
     }
   }
   ```

2. Deploy:
   ```bash
   cd dashboard_app
   vercel --prod
   ```

---

## Critical Files Summary

1. `lib/resistance/analytics/analytics.ex` - Core tracking logic
2. `lib/resistance/game.ex` - Game win tracking (5 locations)
3. `lib/resistance_web/channels/analytics_channel.ex` - WebSocket real-time
4. `dashboard_app/src/services/phoenixChannel.ts` - Frontend connection
5. `priv/repo/migrations/*_create_analytics_stats.exs` - Database schema

---

## Dependencies to Add

### Elixir
```elixir
# mix.exs
{:cors_plug, "~> 3.0"}
```

### React
```bash
npm install phoenix zustand
npm install -D tailwindcss postcss autoprefixer
```

---

## Architecture Decisions

1. **Async Tracking**: Using `Task.Supervisor` ensures game logic never blocks
2. **Single Table**: Flexible schema for adding metrics without migrations
3. **WebSocket**: Real-time updates without polling overhead
4. **Separate Deploy**: React app independent of Phoenix for flexibility
5. **No Auth**: Public stats, read-only access

---

## Performance Considerations

- Atomic database updates prevent race conditions
- Fire-and-forget tracking never blocks game
- WebSocket is efficient (subscribe once, receive updates)
- Single table with index on `metric_name` is fast

---

## Next Steps After Implementation

1. Add historical snapshots for trend charts
2. Add per-room analytics
3. Add visitor retention metrics
4. Implement caching layer (Cachex) if needed at scale
