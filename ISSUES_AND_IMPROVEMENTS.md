# Code Issues and Improvements Tracker

Last Updated: 2026-01-11

## 🔴 Critical Issues (Must Fix)

### 1. Missing Input Validation - Vote Injection Possible
**Status**: ❌ Not Fixed
**Location**: `lib/resistance/game.ex:232, 247`
**Severity**: Critical - Security vulnerability

**Problem**: Vote handlers don't validate player identity or permissions:
- `vote_for_team/3`: Doesn't verify player_id is actually in the game
- `vote_for_mission/3`: Doesn't verify player is on the quest team
- Malicious client could vote multiple times or vote as other players

**Current Code**:
```elixir
def handle_cast({:vote_for_team, player_id, vote}, state) do
  updated_team_votes = Map.put(state.team_votes, player_id, vote)  # ⚠️ No validation!
  # ...
end

def handle_cast({:vote_for_mission, player_id, vote}, state) do
  updated_quest_votes = Map.put(state.quest_votes, player_id, vote)  # ⚠️ No validation!
  # ...
end
```

**Fix Required**:
```elixir
def handle_cast({:vote_for_team, player_id, vote}, state) do
  # Validate player exists
  if !Enum.any?(state.players, fn p -> p.id == player_id end) do
    Logger.warning("Invalid vote attempt from #{player_id}")
    {:noreply, state}
  else
    # Process vote...
  end
end

def handle_cast({:vote_for_mission, player_id, vote}, state) do
  # Validate player is on quest team
  player = Enum.find(state.players, fn p -> p.id == player_id end)
  if !player || !player.on_quest do
    Logger.warning("Invalid mission vote from #{player_id}")
    {:noreply, state}
  else
    # Process vote...
  end
end
```

---

### 2. Tick Timer Memory Leak on Early Stage End
**Status**: ❌ Not Fixed
**Location**: `lib/resistance/game.ex:239, 256`
**Severity**: Critical - Memory leak

**Problem**: When voting completes early (all votes in), the code cancels `timer_ref` but NOT `tick_ref`. This leaves the tick timer running indefinitely, sending messages every second.

**Current Code**:
```elixir
def handle_cast({:vote_for_team, player_id, vote}, state) do
  # ...
  if map_size(updated_team_votes) == length(state.players) do
    if new_state.timer_ref, do: Process.cancel_timer(new_state.timer_ref)
    # ⚠️ Missing: cancel tick_ref!
    send(self(), {:end_stage, :voting})
  end
end
```

**Fix Required**:
```elixir
if map_size(updated_team_votes) == length(state.players) do
  if new_state.timer_ref, do: Process.cancel_timer(new_state.timer_ref)
  if new_state.tick_ref, do: Process.cancel_timer(new_state.tick_ref)  # ← Add this
  send(self(), {:end_stage, :voting})
end
```

**Affected Lines**: 239, 256 (both vote handlers)

---

### 3. Improper Supervision - Pregame Directly Spawns Game
**Status**: ❌ Not Fixed
**Location**: `lib/resistance/pregame.ex:301`
**Severity**: High - Violates OTP supervision principles

**Problem**: Pregame.Server calls `Game.Server.start_link()` directly instead of using DynamicSupervisor. This creates an unsupervised link outside the supervision tree.

**Current Code**:
```elixir
def handle_info(:start_game, state) do
  if all_ready do
    case Game.Server.start_link(state.room_code, state.players) do  # ⚠️ Wrong!
      {:ok, _pid} -> Resistance.Analytics.increment_stat("games_started")
      # ...
    end
  end
end
```

**Fix Required**:
```elixir
def handle_info(:start_game, state) do
  if all_ready do
    case DynamicSupervisor.start_child(
      Resistance.RoomSupervisor,
      {Game.Server, {state.room_code, state.players}}
    ) do
      {:ok, _pid} ->
        Resistance.Analytics.increment_stat("games_started")
        broadcast(state.room_code, :game_started, %{})
      {:error, reason} ->
        Logger.error("Failed to start game: #{inspect(reason)}")
        broadcast(state.room_code, :error, "Failed to start game. Please try again.")
    end
  end
end
```

**Additional Issue**: No user notification on game start failure (lines 301-308)

---

### 4. No King Stage Validation in Team Selection
**Status**: ❌ Not Fixed
**Location**: `lib/resistance/game.ex:205`
**Severity**: High - Game state corruption possible

**Problem**: `toggle_quest_member` only validates that the caller is the king, but doesn't verify the game is in `:party_assembling` stage. King could select team during voting or other stages.

**Current Code**:
```elixir
def handle_call({:toggle_quest_member, king_id, player_id}, _from, state) do
  cond do
    find_king(state.players).id != king_id ->
      {:reply, {:error, "You are not the king"}, state}
    # ⚠️ Missing stage validation!
    is_team_full(...) -> ...
  end
end
```

**Fix Required**:
```elixir
def handle_call({:toggle_quest_member, king_id, player_id}, _from, state) do
  cond do
    state.stage != :party_assembling ->
      {:reply, {:error, "Team selection only during party assembling"}, state}
    find_king(state.players).id != king_id ->
      {:reply, {:error, "You are not the king"}, state}
    # ...
  end
end
```

---

## 🟡 High Priority (Should Fix)

### 5. Inefficient Player List - O(n) Lookups
**Status**: ❌ Not Fixed
**Location**: `lib/resistance/game.ex:170-189`
**Severity**: High - Performance anti-pattern

**Problem**: Using `List` for players requires O(n) iteration for every lookup/update. While acceptable for 5 players, it's poor architectural practice.

**Impact**:
- `find_king/1`: O(n) every stage transition
- `get_self/2` in LiveView: O(n) on every state update
- `toggle_quest_member`: O(n) Enum.map to update single player
- `remove_player`: O(n) filter + multiple O(n) operations

**Current**: `players: [Player]`
**Better**: `players: %{player_id => %Player{}}`

**Example Refactor**:
```elixir
# Before
updated_players = Enum.map(state.players, fn player ->
  if player.id == player_id do
    %Player{player | on_quest: !player.on_quest}
  else
    player
  end
end)

# After (O(1))
updated_players = Map.update!(state.players, player_id, fn player ->
  %Player{player | on_quest: !player.on_quest}
end)
```

---

### 6. Inconsistent Timer API Usage
**Status**: ❌ Not Fixed
**Location**: Multiple files
**Severity**: Medium - Code consistency

**Problem**: Mixing `:timer` module and `Process` timer functions:
- `pregame.ex:172, 206`: Uses `:timer.cancel/1`
- `pregame.ex:188, 260`: Uses `Process.cancel_timer/1`
- `game.ex`: Now uses `Process.send_after/3` (good!)

**Why This Matters**:
- `Process.send_after/3` is more efficient (native BEAM, no timer server)
- `:timer` module spawns a separate process
- Mixing APIs is confusing for maintainers

**Fix**: Standardize on `Process` module throughout:
```elixir
# Replace all occurrences of:
:timer.cancel(ref)          → Process.cancel_timer(ref)
:timer.send_after(ms, ...)  → Process.send_after(self(), ..., ms)
```

---

### 7. Name Validation Called Twice
**Status**: ❌ Not Fixed
**Location**: `lib/resistance/pregame.ex:246-247`
**Severity**: Low - Inefficiency

**Problem**: `valid_name/2` is called twice on the same inputs.

**Current Code**:
```elixir
def handle_call({:add_player, id, name}, _from, state) do
  cond do
    valid_name(name, state.players) != :ok ->
      {:reply, valid_name(name, state.players), state}  # ⚠️ Called twice!
```

**Fix**:
```elixir
def handle_call({:add_player, id, name}, _from, state) do
  validation_result = valid_name(name, state.players)

  cond do
    validation_result != :ok ->
      {:reply, validation_result, state}
```

---

### 8. Duplicate Vote Prevention Missing
**Status**: ❌ Not Fixed
**Location**: `lib/resistance/game.ex:232, 247`
**Severity**: Medium - Game fairness

**Problem**: No check prevents a player from changing their vote multiple times rapidly. While the last vote wins (Map overwrites), this could enable vote manipulation or confusion.

**Fix Options**:
1. **Simple**: Ignore subsequent votes after first vote
2. **Better**: Allow vote changes but broadcast each change
3. **Best**: Track vote history for analytics/debugging

**Example**:
```elixir
def handle_cast({:vote_for_team, player_id, vote}, state) do
  # Option 1: Reject if already voted
  if Map.has_key?(state.team_votes, player_id) do
    {:noreply, state}  # Silent ignore or broadcast error
  else
    # Process vote...
  end
end
```

---

### 9. Empty Room Handling in Game
**Status**: ❌ Not Fixed
**Location**: `lib/resistance/game.ex:263-297`
**Severity**: Medium - Resource cleanup

**Problem**: `remove_player` handles win conditions if player count becomes unbalanced, but doesn't handle the edge case where ALL players leave.

**Current Behavior**:
- If all players disconnect, game server continues running
- No automatic cleanup or shutdown
- State machine still ticks through stages with 0 players

**Fix Required**:
```elixir
def handle_cast({:remove_player, player_id}, state) do
  updated_players = Enum.filter(state.players, fn player -> player.id != player_id end)

  new_state = cond do
    # NEW: Check if room is empty
    Enum.empty?(updated_players) ->
      Logger.info("Room #{state.room_code}: All players left, shutting down")
      GenServer.stop(self(), :normal)
      state  # Won't be used, but required for cond

    num_bad_guys > num_good_guys ->
      # ... existing logic
  end
end
```

---

## 🟢 Medium Priority (Nice to Have)

### 10. Player Struct in Wrong File
**Status**: ❌ Not Fixed
**Location**: `lib/resistance/game.ex:1-22`
**Severity**: Low - Code organization

**Problem**: `Player` module is defined in `game.ex` but used across multiple modules (pregame, game, liveviews).

**Fix**: Move to `lib/resistance/player.ex` and `alias` where needed.

---

### 11. Magic Numbers Scattered Throughout
**Status**: ❌ Not Fixed
**Locations**: Timer values (3000, 5000, 15000) hardcoded
**Severity**: Low - Maintainability

**Problem**: Stage durations are hardcoded magic numbers, making it hard to:
- Adjust timings for testing
- Configure different game modes (quick game, long game)
- Understand what the numbers mean

**Fix**: Use module attributes:
```elixir
@stage_durations %{
  init: 3_000,              # 3 seconds between rounds
  party_assembling: 15_000,  # 15 seconds to select team
  voting: 15_000,            # 15 seconds to vote
  quest: 15_000,             # 15 seconds for quest
  quest_reveal: 5_000,       # 5 seconds to show results
  pregame_countdown: 5_000   # 5 seconds before game starts
}

# Usage
start_stage_timer(state, :voting, @stage_durations[:voting])
```

---

### 12. Business Logic Mixed with GenServer Code
**Status**: ❌ Not Fixed
**Severity**: Low - Testability

**Problem**: Pure business logic functions are mixed with GenServer callbacks, making them harder to test in isolation.

**Extract to** `lib/resistance/game_logic.ex`:
- `check_win_condition/1` (line 476)
- `make_players/1` (line 345)
- `check_team_approved/1` (line 548)
- `get_result/1` (line 539)
- `assign_next_king/1` (line 494)
- `is_team_full/3` (line 517)

**Benefits**:
- Test business logic without spawning GenServers
- Reuse logic in other contexts
- Clearer separation of concerns

---

### 13. CSRF Token as Player ID is Fragile
**Status**: ❌ Not Fixed
**Location**: All LiveViews use `session["_csrf_token"]`
**Severity**: Low - Identity management

**Problem**: CSRF tokens:
- Can rotate on certain security events
- Aren't designed for persistent identity
- Could theoretically collide (unlikely but possible)

**Fix**: Generate UUID in session:
```elixir
# In router.ex plug
def put_player_id(conn, _opts) do
  player_id = get_session(conn, :player_id) || Ecto.UUID.generate()
  put_session(conn, :player_id, player_id)
end

# In LiveView mount
player_id = get_connect_params(socket)["player_id"] || session["player_id"]
```

---

### 14. No Rate Limiting
**Status**: ❌ Not Fixed
**Severity**: Low - DoS potential

**Problem**: No protection against:
- Vote spamming
- Chat message floods
- Rapid ready/unready toggling
- Team selection spam by king

**Fix Options**:
1. Use `:hammer` library for rate limiting
2. Simple throttle in GenServer (track last action timestamp)
3. LiveView throttle with `phx-throttle` attribute

**Example with :hammer**:
```elixir
def handle_cast({:vote_for_team, player_id, vote}, state) do
  case Hammer.check_rate("vote:#{player_id}", 60_000, 5) do
    {:allow, _count} ->
      # Process vote
    {:deny, _limit} ->
      Logger.warning("Rate limit exceeded for player #{player_id}")
      {:noreply, state}
  end
end
```

---

### 15. Dialyzer Warning - Unreachable Pattern
**Status**: ❌ Not Fixed
**Location**: `lib/resistance/game.ex:624` (in `end_game/2`)
**Severity**: Very Low - Code cleanliness

**Problem**: The pattern `_ ->` in `end_game/2` can never match because the function only receives `:good` or `:bad`.

**Current Code**:
```elixir
defp end_game(room_code, winning_team) do
  case winning_team do
    :good -> Resistance.Analytics.increment_stat("good_team_wins")
    :bad -> Resistance.Analytics.increment_stat("bad_team_wins")
    _ -> :ok  # ⚠️ This can never match!
  end
end
```

**Fix**:
```elixir
defp end_game(room_code, winning_team) do
  case winning_team do
    :good -> Resistance.Analytics.increment_stat("good_team_wins")
    :bad -> Resistance.Analytics.increment_stat("bad_team_wins")
  end
  GenServer.stop(via_tuple(room_code))
end
```

---

### 16. Inconsistent Broadcast Timing
**Status**: ❌ Not Fixed
**Location**: Throughout `game.ex`
**Severity**: Very Low - Potential race conditions

**Problem**: Sometimes broadcasts happen before state updates, sometimes after:
- Line 226: Broadcasts then updates state
- Line 363: Updates state then broadcasts
- Line 375: Updates state then broadcasts

**Best Practice**: Always broadcast AFTER updating state to ensure consistency.

---

### 17. Missing Terminate Cleanup in Game.Server
**Status**: ❌ Not Fixed
**Location**: `lib/resistance/game.ex`
**Severity**: Low - Resource cleanup

**Problem**: `Game.Server` doesn't implement `terminate/2` callback to clean up timers.

**Fix**:
```elixir
@impl true
def terminate(_reason, state) do
  # Clean up timers on termination
  if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
  if state.tick_ref, do: Process.cancel_timer(state.tick_ref)
  :ok
end
```

Note: Pregame.Server already implements this correctly (line 352).

---

## ✅ Recently Fixed Issues

### Server-Side Timer Synchronization
**Status**: ✅ FIXED (2026-01-11)
**Improvement**: Implemented centralized timer in GenServer with periodic broadcasts

**What Changed**:
- GenServer owns `stage_end_time` and broadcasts remaining time every second
- LiveView receives time updates via PubSub instead of running independent timer
- Eliminates timer drift between clients
- Late joiners see accurate time immediately
- Works correctly when browser tab is backgrounded

**Files Modified**:
- `lib/resistance/game.ex`: Added `start_stage_timer/3`, `broadcast_time_update/1`, `handle_info(:tick)`
- `lib/resistance_web/live/game/game_live.ex`: Removed client timer logic, added `handle_info({:time_update, ...})`

---

### Pregame Timer Race Condition
**Status**: ✅ FIXED (Previously)
**Location**: `lib/resistance/pregame.ex`

**What Changed**:
- Stores timer reference in state (line 163)
- Cancels timer when players leave or un-ready (lines 172, 206)
- Verifies BOTH count AND ready status before starting (lines 296-298)

---

### Event-Driven Voting
**Status**: ✅ FIXED (Previously)
**Location**: `lib/resistance/game.ex:238-241, 254-257`

**What Changed**:
- Game advances immediately when all votes are in
- Cancels timer and sends `{:end_stage, stage}` message
- Significantly improved UX (no waiting for timer)

---

### Multiple Concurrent Rooms
**Status**: ✅ FIXED (Previously)
**Implementation**: Registry + DynamicSupervisor pattern

**What Changed**:
- Both `Pregame.Server` and `Game.Server` use `{:via, Registry, ...}` naming
- Spawned via `DynamicSupervisor` for independent lifecycle
- Unlimited concurrent rooms supported
- Room isolation via unique room codes

---

## Implementation Priority

**Phase 1 - Critical (Immediate)**:
1. ⚠️ Fix vote validation (#1)
2. ⚠️ Fix tick timer leak (#2)
3. ⚠️ Fix king stage validation (#4)
4. ⚠️ Fix supervision tree (#3)

**Phase 2 - High Priority (Soon)**:
5. Change player list to map (#5)
6. Standardize timer APIs (#6)
7. Add duplicate vote prevention (#8)
8. Handle empty rooms in Game (#9)

**Phase 3 - Polish (Eventually)**:
9. Reorganize files (#10)
10. Extract magic numbers (#11)
11. Extract business logic (#12)
12. Use UUID for player IDs (#13)
13. Add rate limiting (#14)
14. Fix Dialyzer warning (#15)
15. Standardize broadcast timing (#16)
16. Add Game.Server terminate callback (#17)

---

## Testing Checklist

After implementing fixes, verify:
- [x] Game doesn't start if player un-readies during countdown
- [x] Game advances immediately when all votes are in
- [x] Timer syncs correctly across all clients
- [x] Multiple simultaneous games work
- [ ] Invalid votes are rejected (player not in game)
- [ ] Invalid mission votes are rejected (player not on quest)
- [ ] Tick timer stops when stage ends early
- [ ] Game shuts down when all players leave
- [ ] King cannot select team during wrong stage

---

## Performance Metrics

Current complexity analysis:
- **Player lookup**: O(n) - should be O(1) with map
- **King finding**: O(n) per stage - should be O(1)
- **Vote validation**: O(1) for Map.put, but no validation
- **Broadcast**: O(m) where m = number of subscribed clients (acceptable)

With player map refactor:
- All operations become O(1)
- Estimated 10-20% performance improvement (negligible for 5 players)
- Main benefit: cleaner, more idiomatic Elixir code
