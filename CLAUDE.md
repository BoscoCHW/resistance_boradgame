# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) or Gemini when working with code in this repository.

## Project Overview

This is an **Avalon/Resistance multiplayer party game** built with Phoenix LiveView. It's a real-time web application where 5 players per room compete in a social deduction game. The architecture uses **multi-room in-memory GenServer state management** (not database-backed) with Phoenix PubSub for real-time broadcasting. **Unlimited concurrent rooms** can run simultaneously, each with isolated state using 6-character room codes.

## Essential Commands

### Development Workflow
```bash
# First-time setup (installs deps, creates DB, builds assets)
mix setup

# Start development server
mix phx.server

# Start with interactive Elixir shell
iex -S mix phx.server

# Run all tests
mix test

# Run specific test file
mix test test/resistance/game_test.exs

# Run tests matching a pattern
mix test --only <tag_name>
```

### Database Commands
```bash
# Create database
mix ecto.create

# Run migrations
mix ecto.migrate

# Reset database (drop, create, migrate, seed)
mix ecto.reset

# Drop database
mix ecto.drop
```

### Asset Management
```bash
# Rebuild assets (Tailwind CSS + esbuild)
mix assets.build

# Install asset tools
mix assets.setup

# Production asset compilation
mix assets.deploy
```

### Dependencies
```bash
# Get dependencies
mix deps.get

# Update specific dependency (example: ecto)
mix deps.update ecto

# Compile dependencies
mix deps.compile
```

## Architecture Overview

### Core State Management Pattern

This application uses **GenServers as the primary state container**, NOT the database. Understanding this is critical:

1. **DynamicSupervisor** (`lib/resistance/application.ex`)
   - `Resistance.RoomSupervisor` spawns and supervises room processes on-demand
   - Strategy: `:one_for_one` - isolated failure handling per room
   - Started by Application supervisor on boot
   - Allows unlimited concurrent rooms

2. **Registry** (`lib/resistance/application.ex`)
   - `Resistance.RoomRegistry` provides process lookup by room code
   - Keys: `{:pregame, room_code}` and `{:game, room_code}`
   - Type: `keys: :unique` - one process per key
   - Enables distributed process discovery

3. **RoomCode** (`lib/resistance/room_code.ex`)
   - Generates and validates 6-character alphanumeric codes
   - Format: A-Z, 2-9 (excludes confusing characters like 0, O, 1, I)
   - Functions: `generate()`, `validate(code)`, `normalize(code)`
   - Used for Registry keys, PubSub topics, and URL paths

4. **Pregame.Server** (`lib/resistance/pregame.ex`)
   - Per-room GenServer spawned by DynamicSupervisor on room creation
   - Manages lobby state (up to 5 players per room)
   - Validates player names (per room, not globally)
   - Tracks ready status and spawns Game.Server when 5 players ready
   - Uses `Process.flag(:trap_exit, true)` to detect game termination
   - Registration: `{:via, Registry, {Resistance.RoomRegistry, {:pregame, room_code}}}`
   - Inactivity cleanup: 3-minute timer → self-terminates if empty

5. **Game.Server** (`lib/resistance/game.ex`)
   - Per-room GenServer spawned by Pregame.Server when game starts
   - Manages ALL game state in-memory (room_code, players, votes, stage, outcomes)
   - Self-terminates on game end via `GenServer.stop/1`
   - Registration: `{:via, Registry, {Resistance.RoomRegistry, {:game, room_code}}}`
   - Each room has completely isolated game state

6. **Player Identification**
   - CSRF tokens from Phoenix session used as player IDs
   - Stored in `socket.assigns.self` in LiveView
   - Persists across LiveView navigation within a room

### State Machine (Game Stages)

The game progresses through 6 distinct stages with automatic timer-based transitions:

```
:init (3s)
  ↓
:party_assembling (15s) ← King selects team
  ↓
:voting (15s) ← All vote approve/reject
  ↓ (if approved)
:quest (15s) ← Team votes assist/sabotage
  ↓
:quest_reveal (5s) ← Show results
  ↓
:init (next round) OR :end_game
```

**Important**: Timers send messages to self (`:timer.send_after/3`), handled in `handle_info/2`. Missing votes auto-fill as `:assist` to prevent hanging.

### Real-time Communication Flow (Room-Scoped)

```
Frontend (LiveView) → Backend (GenServer) → PubSub (Room Topic) → Room Clients

Example (for room ABC123):
1. User clicks button → phx-click="vote_for_team"
2. LiveView.handle_event → Game.Server.vote_for_team(room_code, player_id, vote)
3. GenServer updates state for that room
4. GenServer broadcasts: Phoenix.PubSub.broadcast(Resistance.PubSub, "room:ABC123", {:update, state})
5. All LiveViews subscribed to "room:ABC123" receive: handle_info({:update, state}, socket)
6. Templates re-render with new state
7. Players in other rooms (e.g., XYZ789) see nothing - complete isolation
```

**Key Points:**
- Each room has its own PubSub topic: `"room:{room_code}"`
- LiveViews subscribe to specific room topic via `Pregame.Server.subscribe(room_code)` or `Game.Server.subscribe(room_code)`
- Room isolation guarantees players only see updates from their room
- Multiple concurrent games can run without interference

### Component Hierarchy

```
LiveView Pages (lib/resistance_web/live/)
├── HomeLive (/) - Room creation/joining, name entry
├── LobbyLive (/lobby/:room_code) - 5-player waiting room per room
└── GameLive (/game/:room_code) - Main game interface per room
    ├── MainCard - Stage-specific central UI
    ├── SideBar - Player list, quest tracker, role display
    ├── ChatBox - Real-time messaging
    └── TopBar - Help, sound toggle, quit
```

**LiveComponents** (stateful): `SoundToggle`, `QuitButton`, `HowToPlayShortcut`

**Routes:**
- `/` - Home page (create or join room)
- `/lobby/:room_code` - Lobby for specific room (e.g., `/lobby/ABC123`)
- `/game/:room_code` - Active game for specific room (e.g., `/game/ABC123`)
- Room codes are validated and normalized (uppercase) in `handle_params`

## Key Game Logic Rules

### Role Assignment
```elixir
num_bad = ceil(player_count / 3)  # Always 2 for 5 players (⅔)
num_good = player_count - num_bad  # Always 3 for 5 players (⅓)
# Roles shuffled and assigned on game start
```

### Quest Team Sizes
Per round: `[2, 3, 2, 3, 3]` players

### Voting Rules
- **Team approval**: Strict majority required (`approvals > total_players / 2`)
- **Quest outcome**: ONE `:sabotage` vote → mission fails
- **Auto-win conditions**:
  - 4+ consecutive team rejections → Spies win
  - First team to 3 quest wins → Game ends

### Information Asymmetry
- **Spies**: Know each other's identities (see names in UI if `player.role == :bad`)
- **Good guys**: No knowledge of roles, must deduce from behavior

## Testing Patterns

Tests use `ExUnit` with async execution:

```elixir
defmodule Resistance.GameTest do
  use ExUnit.Case, async: true
  import Phoenix.ChannelTest

  # Test Player struct operations
  test "create new player" do
    player = Player.new(1, "Alice", :good)
    assert player.id == 1
  end
end
```

**Test locations**:
- `test/resistance/game_test.exs` - Game logic tests
- `test/resistance/pregame_test.exs` - Lobby logic tests
- `test/resistance_web/` - Web layer tests

## Important Implementation Notes

### Session and Routing
- Player IDs derived from `_csrf_token` in session
- Routes use dynamic room codes: `/lobby/:room_code` and `/game/:room_code`
- Room codes validated on `handle_params` - invalid codes redirect to `/`
- Routes redirect to `/` if room doesn't exist or player not in room
- No database persistence for game state - all state in room-specific GenServers

### Database Status
PostgreSQL is configured but **NOT used for game state**. The database exists for:
- Future features (leaderboards, game history)
- Phoenix framework requirements
- Current game state lives entirely in GenServer memory

### Asset Pipeline
- **Tailwind CSS**: Configured in `assets/tailwind.config.js`
- **esbuild**: Configured in `config/config.exs`
- **Custom CSS**: Organized by page in `assets/css/pages/`
- **Images**: Medieval/fantasy theme in `priv/static/images/`

### Deployment Considerations
- Single-server architecture (no distributed GenServer)
- Multi-room support allows unlimited concurrent games on single node
- All room state lost on server restart (no persistence)
- No persistence between sessions by design
- PubSub configured for single-node (can be upgraded to Redis/cluster for distributed deployment)
- Room isolation ensures one room crash doesn't affect others
- Inactivity cleanup (3-minute timer) prevents memory leaks from abandoned rooms

## Common Development Scenarios

### Adding a New Game Stage
1. Add stage atom to `@stages` module attribute in `game.ex`
2. Add timer handling in `handle_info({:end_stage, :your_stage}, state)`
3. Create corresponding MainCard template in `main_card.ex`
4. Add stage transition logic
5. Update state machine documentation

### Modifying Player Actions
1. Add event handler in `GameLive.handle_event/3`
2. Get `room_code` from `socket.assigns.room_code`
3. Call GenServer function via `Game.Server.your_function(room_code, player_id, ...)`
4. Update GenServer state in `handle_call` or `handle_cast`
5. Broadcast state change via `broadcast(room_code, :update, new_state)`
6. Update template to show new UI element

**Important:** All GenServer functions now require `room_code` as first parameter to target the correct room instance.

### Debugging Real-time Issues
- Use `iex -S mix phx.server` for interactive debugging
- Insert `IO.inspect(state, label: "Debug")` in GenServer callbacks
- Check PubSub subscription for specific room: `Phoenix.PubSub.subscribers(Resistance.PubSub, "room:ABC123")`
- Check all active rooms: `Registry.select(Resistance.RoomRegistry, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])`
- Monitor GenServer processes: `:observer.start()` in iex
- Find room process: `Registry.lookup(Resistance.RoomRegistry, {:pregame, "ABC123"})` or `{:game, "ABC123"}`

## Configuration Notes

### PostgreSQL Requirements
- **Username**: `postgres`
- **Password**: `postgres`
- **Port**: 5432 (default)
- Start via: `brew services start postgresql` (Homebrew) or Docker

### Environment-specific Config
- **Development**: `config/dev.exs` - Live reload enabled, debug logging
- **Test**: `config/test.exs` - Sandbox mode, SQL logging
- **Production**: `config/prod.exs` + `config/runtime.exs` - Release configuration

### Port Configuration
Default dev server runs on `localhost:4000`

## Dependencies to Note

- **Phoenix LiveView ~> 0.18**: Real-time UI without JavaScript frameworks
- **Ecto ~> 3.11**: Required for Elixir 1.18+ compatibility (3.9 has `dynamic/0` type conflict)
- **Tailwind ~> 0.1.8**: CSS framework
- **esbuild ~> 0.5**: JavaScript bundler

##################################################################

# Using Gemini CLI for Large Codebase Analysis
When analyzing large codebases or multiple files that might exceed context limits, use the Gemini CLI with its massive context window. Use `gemini -p` to leverage Google Gemini's large context capacity.

## File and Directory Inclusion Syntax
Use the `@` syntax to include files and directories in your Gemini prompts. The paths should be relative to WHERE you run the gemini command:

### Examples:
```bash
gemini -p "@src/main.py Explain this file's purpose and structure"

# Multiple files:
gemini -p "@package.json @src/index.js Analyze the dependencies used in the code"

# Entire directory:
gemini -p "@src/ Summarize the architecture of this codebase"

# Multiple directories:
gemini -p "@src/ @tests/ Analyze test coverage for the source code"

# Current directory and subdirectories:
gemini -p "@./ Give me an overview of this entire project"

# Or use --all_files flag:
gemini --all_files -p "Analyze the project structure and dependencies"
```

# When to Use Gemini CLI
Use gemini -p when:
- Analyzing entire codebases or large directories
- Comparing multiple large files
- Need to understand project-wide patterns or architecture
- Current context window is insufficient for the task
- Working with files totaling more than 100KB
- Verifying if specific features, patterns, or security measures are implemented
- Checking for the presence of certain coding patterns across the entire codebase

# Important Notes
- Paths in @ syntax are relative to your current working directory when invoking gemini
- The CLI will include file contents directly in the context
- No need for --yolo flag for read-only analysis
- Gemini's context window can handle entire codebases that would overflow Claude's context
- When checking implementations, be specific about what you're looking for to get accurate results # Using Gemini CLI for Large Codebase Analysis
