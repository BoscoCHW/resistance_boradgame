# Multi-Room Implementation Guide

## Status: ✅ COMPLETED

This document tracks the implementation of multi-room/multi-lobby support with 6-character room codes.

## ✅ Completed Components

### 1. Application Infrastructure
- **File**: `lib/resistance/application.ex`
- ✅ Added `Resistance.RoomRegistry` - Registry for unique process naming
- ✅ Added `Resistance.RoomSupervisor` - DynamicSupervisor for spawning rooms
- ✅ Removed singleton Pregame.Server from supervision tree

### 2. Room Code Module
- **File**: `lib/resistance/room_code.ex` (NEW)
- ✅ Room code generation (6 characters, alphanumeric, no ambiguous chars)
- ✅ Room code validation
- ✅ PubSub topic helper: `pubsub_topic(room_code)`
- ✅ Registry key helpers: `pregame_key(room_code)`, `game_key(room_code)`

### 3. Pregame.Server Refactoring
- **File**: `lib/resistance/pregame.ex`
- ✅ Removed singleton pattern (`name: __MODULE__` → `name: via_tuple(room_code)`)
- ✅ All functions now accept `room_code` as first parameter
- ✅ Added `find_or_create(room_code)` - creates room if doesn't exist
- ✅ Added `find(room_code)` - finds existing room
- ✅ Added `room_exists?(room_code)` - checks if room exists
- ✅ Room-specific PubSub topics using `RoomCode.pubsub_topic(room_code)`
- ✅ **Inactivity cleanup**: Rooms shut down after 3 minutes of being empty
- ✅ Changed `max_players()` from 2 to 5

**API Changes**:
```elixir
# Old
Pregame.Server.add_player(id, name)
Pregame.Server.subscribe()

# New
Pregame.Server.add_player(room_code, id, name)
Pregame.Server.subscribe(room_code)
```

### 4. Game.Server Refactoring
- **File**: `lib/resistance/game.ex`
- ✅ Removed singleton pattern
- ✅ All functions now accept `room_code` as first parameter
- ✅ Added `find(room_code)` - finds existing game
- ✅ Added `room_exists?(room_code)` - checks if game exists
- ✅ Room-specific PubSub topics
- ✅ Updated all `broadcast()` calls to include `room_code`
- ✅ Updated all `end_game()` calls to include `room_code`
- ✅ `init/1` now accepts `{room_code, pregame_state}` tuple
- ✅ State now includes `room_code` field

**API Changes**:
```elixir
# Old
Game.Server.start_link(players)
Game.Server.get_state()
Game.Server.subscribe()
Game.Server.vote_for_team(player_id, vote)

# New
Game.Server.start_link(room_code, players)
Game.Server.get_state(room_code)
Game.Server.subscribe(room_code)
Game.Server.vote_for_team(room_code, player_id, vote)
```

---

## ✅ Completed: LiveView Updates

The following LiveView files have been updated to use the new room-code-based API:

### 1. HomeLive (`lib/resistance_web/live/home/home_live.ex`) ✅

**Completed Changes**:
- ✅ Added `room_code` and `is_creating` to mount assigns
- ✅ Updated `validate` handler to validate both name and room_code
- ✅ Added `create_room` handler to generate new room code
- ✅ Updated `join` handler to accept room_code and navigate to `/lobby/:room_code`
- ✅ Added `cancel_create` handler to reset create flow

**UI Changes** (`lib/resistance_web/live/home/home_live.html.heex`):
- ✅ Dynamic modal title: "Create New Room" vs "Join a Room"
- ✅ Room code display when creating (prominently shows 6-char code)
- ✅ Room code input field when joining
- ✅ "Create New Room" and "Join Room" buttons toggle flow
- ✅ "Cancel" button to exit create mode

### 2. LobbyLive (`lib/resistance_web/live/lobby/lobby_live.ex`) ✅

**Completed Changes**:
- ✅ Added `room_code` to mount assigns
- ✅ Updated `handle_params/3` to extract and validate room_code from URL
- ✅ Added redirect to game if game already started for this room
- ✅ Added redirect to home if player not in lobby
- ✅ Updated `subscribe` to use room-specific topic
- ✅ Updated all `Pregame.Server` calls to include room_code
- ✅ Updated `handle_info(:tick, ...)` to navigate to `/game/:room_code`
- ✅ Updated `terminate/2` to safely remove player with room_code

**UI Changes** (`lib/resistance_web/live/lobby/lobby_live.html.heex`):
- ✅ Room code displayed prominently at top with dark background
- ✅ Updated `top_bar` component to pass `room_code`

### 3. GameLive (`lib/resistance_web/live/game/game_live.ex`) ✅

**Completed Changes**:
- ✅ Added `room_code` to mount assigns
- ✅ Updated `handle_params/3` to extract and validate room_code from URL
- ✅ Added redirect to home if game doesn't exist or player not in game
- ✅ Updated `subscribe` to use room-specific topic
- ✅ Updated all `Game.Server` calls to include room_code:
  - `toggle_quest_member`
  - `vote_for_team`
  - `vote_for_mission`
  - `message`

**UI Changes** (`lib/resistance_web/live/game/game_live.html.heex`):
- ✅ Room code displayed at top center with dark background
- ✅ Updated `top_bar` component to pass `room_code`

### 4. Router (`lib/resistance_web/router.ex`) ✅

**Completed Changes**:
- ✅ Updated `/lobby` route to `/lobby/:room_code`
- ✅ Updated `/game` route to `/game/:room_code`
- ✅ Home route unchanged (catch-all)

### 5. TopBar Components ✅

**Completed Changes**:
- ✅ Updated `top_bar.ex` to accept `room_code` attribute
- ✅ Updated `quit_button.ex` to use room_code when removing players
- ✅ Fixed singleton `GenServer.whereis(Game.Server)` to use `Game.Server.room_exists?(room_code)`

---

## Testing Checklist

After completing LiveView updates, verify:

- [ ] Can create a new room from home page
- [ ] Generated room code is displayed clearly
- [ ] Can join an existing room with room code
- [ ] Room code validation works (6 chars, alphanumeric)
- [ ] Multiple rooms can exist simultaneously
- [ ] Players in different rooms don't see each other
- [ ] Room shuts down 3 minutes after all players leave
- [ ] Cannot join non-existent room
- [ ] Cannot join full room (5 players)
- [ ] Game functions correctly within a room
- [ ] Room code persists in URL during navigation

---

## Implementation Priority

1. **High Priority** (Required for basic functionality):
   - [ ] Update HomeLive to show Create/Join UI
   - [ ] Update router to accept room_code params
   - [ ] Update LobbyLive to use room_code
   - [ ] Update GameLive to use room_code

2. **Medium Priority** (UX improvements):
   - [ ] Add "Copy Room Code" button
   - [ ] Show room code prominently in lobby/game
   - [ ] Add room code to page title
   - [ ] Show number of players in room

3. **Low Priority** (Polish):
   - [ ] Room code auto-formatting (XXX-XXX)
   - [ ] Recently joined rooms list
   - [ ] Room creation options (player count, etc.)

---

## Example UI Flow

### Home Page
```
┌─────────────────────────────────────┐
│         AVALON GAME                 │
│                                     │
│   ┌─────────────────────────────┐  │
│   │  CREATE NEW ROOM            │  │
│   └─────────────────────────────┘  │
│                                     │
│   ┌─────────────────────────────┐  │
│   │  JOIN EXISTING ROOM         │  │
│   └─────────────────────────────┘  │
│                                     │
│   Help           Credits            │
└─────────────────────────────────────┘
```

### Create Room Modal
```
┌─────────────────────────────────────┐
│  Your Room Code: ABC123             │
│  (Click to copy)                    │
│                                     │
│  Enter your name:                   │
│  [________________]                 │
│                                     │
│  [Join Room]                        │
└─────────────────────────────────────┘
```

### Join Room Modal
```
┌─────────────────────────────────────┐
│  Enter Room Code:                   │
│  [______]                           │
│                                     │
│  Enter your name:                   │
│  [________________]                 │
│                                     │
│  [Join Room]                        │
└─────────────────────────────────────┘
```

### Lobby (with room code)
```
┌─────────────────────────────────────┐
│  Room: ABC123  [Copy]               │
│                                     │
│  Players (3/5):                     │
│    🟢 Alice (Ready)                 │
│    🟢 Bob (Ready)                   │
│    ⚪ Charlie                        │
│                                     │
│  [Toggle Ready]  [Leave Room]       │
└─────────────────────────────────────┘
```

---

## Key Architectural Improvements

1. **Scalability**: Can now support unlimited concurrent games
2. **Isolation**: Each room has its own GenServer processes
3. **Resource Management**: Rooms auto-cleanup after inactivity
4. **Flexibility**: Easy to add room-specific configurations later

---

## Migration Notes

- **Breaking Change**: All existing routes will need room codes
- **Session Management**: May want to store "last_room_code" in session
- **Backward Compatibility**: Old bookmarks/links will break (acceptable for v2)
