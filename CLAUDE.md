# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an **Avalon/Resistance multiplayer party game** built with Phoenix LiveView. It's a real-time web application where 5 players compete in a social deduction game. The architecture uses **in-memory GenServer state management** (not database-backed) with Phoenix PubSub for real-time broadcasting.

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

1. **Pregame.Server** (`lib/resistance/pregame.ex`)
   - Singleton GenServer started by Application supervisor
   - Manages lobby state (up to 5 players)
   - Validates player names, tracks ready status
   - Spawns Game.Server when 5 players ready
   - Uses `Process.flag(:trap_exit, true)` to detect game termination

2. **Game.Server** (`lib/resistance/game.ex`)
   - Dynamically spawned per game instance
   - Manages ALL game state in-memory (players, votes, stage, outcomes)
   - Self-terminates on game end via `GenServer.stop/1`
   - Uses named process registration: `{:via, Registry, {Resistance.Registry, :game}}`

3. **Player Identification**
   - CSRF tokens from Phoenix session used as player IDs
   - Stored in `socket.assigns.self` in LiveView
   - Persists across LiveView navigation

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

### Real-time Communication Flow

```
Frontend (LiveView) → Backend (GenServer) → PubSub → All Clients

Example:
1. User clicks button → phx-click="vote_for_team"
2. LiveView.handle_event → Game.Server.vote_for_team/2
3. GenServer updates state
4. GenServer broadcasts: Phoenix.PubSub.broadcast(Resistance.PubSub, "game", {:update, state})
5. All LiveViews receive: handle_info({:update, state}, socket)
6. Templates re-render with new state
```

### Component Hierarchy

```
LiveView Pages (lib/resistance_web/live/)
├── HomeLive (/) - Menu, name entry modal
├── LobbyLive (/lobby) - 5-player waiting room
└── GameLive (/game) - Main game interface
    ├── MainCard - Stage-specific central UI
    ├── SideBar - Player list, quest tracker, role display
    ├── ChatBox - Real-time messaging
    └── TopBar - Help, sound toggle, quit
```

**LiveComponents** (stateful): `SoundToggle`, `QuitButton`, `HowToPlayShortcut`

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
- Routes redirect to `/` if player not in game/lobby
- No database persistence for game state

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
- Game state lost on server restart
- No persistence between sessions by design
- PubSub configured for single-node (can be upgraded to Redis/cluster)

## Common Development Scenarios

### Adding a New Game Stage
1. Add stage atom to `@stages` module attribute in `game.ex`
2. Add timer handling in `handle_info({:end_stage, :your_stage}, state)`
3. Create corresponding MainCard template in `main_card.ex`
4. Add stage transition logic
5. Update state machine documentation

### Modifying Player Actions
1. Add event handler in `GameLive.handle_event/3`
2. Call GenServer function via `Game.Server.your_function/2`
3. Update GenServer state in `handle_call` or `handle_cast`
4. Broadcast state change via `broadcast(:update, new_state)`
5. Update template to show new UI element

### Debugging Real-time Issues
- Use `iex -S mix phx.server` for interactive debugging
- Insert `IO.inspect(state, label: "Debug")` in GenServer callbacks
- Check PubSub subscription: `Phoenix.PubSub.subscribers(Resistance.PubSub, "game")`
- Monitor GenServer processes: `:observer.start()` in iex

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
