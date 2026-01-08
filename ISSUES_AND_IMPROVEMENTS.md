# Code Issues and Improvements Tracker

Generated: 2026-01-06

## 🔴 Critical Issues (Must Fix)

### 1. Pregame Timer Race Condition
**Status**: ✅ FIXED
**Location**: `lib/resistance/pregame.ex:80-94`
**Severity**: Critical - Game can start with wrong player count/status

**Problem**: When all 5 players ready up, a 5-second timer starts. If a player disconnects or un-readies during those 5 seconds, the timer isn't cancelled. The game will start anyway, even with fewer than 5 players or with unready players.

**Current Code**:
```elixir
def handle_cast({:toggle_ready, id}, state) do
  # ...
  case all_ready? do
    true ->
      :timer.send_after(5000, self(), :start_game)  # ⚠️ No reference stored!
    _ -> broadcast(:update, new_state)
  end
end

def handle_info(:start_game, state) do
  if Enum.count(state) == max_players() do  # ⚠️ Doesn't check ready status!
    Game.Server.start_link(state)
  end
end
```

**Fix Required**:
- Store timer reference in state
- Cancel timer if state changes (player disconnects/un-readies)
- Verify BOTH count AND ready status before starting game

---

### 2. Poor UX: Timer-Based Instead of Event-Driven
**Status**: ✅ FIXED
**Location**: `lib/resistance/game.ex` - voting stages (lines 166, 174)
**Severity**: Critical - Poor user experience

**Problem**: Players must wait for the full 15-second timer even if everyone has voted. This creates a sluggish, frustrating experience.

**Current Behavior**:
- All 5 players vote in 2 seconds
- Must wait 13 more seconds for timer to expire
- Game doesn't check if voting is complete

**Fix Required**:
- In `vote_for_team/2`: Check if all votes are in, advance immediately
- In `vote_for_mission/2`: Check if all quest members voted, advance immediately
- Cancel existing timer and send `{:end_stage, stage}` message

---

### 3. LiveView Timer Crash Risk
**Status**: ✅ FIXED
**Location**: `lib/resistance_web/live/game/game_live.ex:49, 56`
**Severity**: Critical - Process crash

**Problem**: Calling `:timer.cancel(nil)` crashes the LiveView process when `timer_ref` is nil.

**Current Code**:
```elixir
:timer.cancel(socket.assigns.timer_ref)  # ⚠️ Crashes if nil!
```

**Fix Required**:
```elixir
if socket.assigns.timer_ref, do: :timer.cancel(socket.assigns.timer_ref)
```

**Affected Files**:
- `lib/resistance_web/live/game/game_live.ex`
- `lib/resistance_web/live/lobby/lobby_live.ex`

---

### 4. LiveView Refresh Bug - No Timer After Reload
**Status**: ✅ FIXED
**Location**: `lib/resistance_web/live/game/game_live.ex:18-28`
**Severity**: Critical - Users miss deadlines

**Problem**: If a user refreshes the page during a timed stage (e.g., `:voting`, `:quest`), they see the game state but no countdown timer appears. They may miss the voting deadline without realizing time is running out.

**Current Behavior**:
- `handle_params/3` loads state but doesn't initialize timer
- Timer logic only in `handle_info({:update, ...})` for state transitions
- User who refreshes sees frozen UI with no countdown

**Fix Required**:
- Extract timer initialization into helper function `start_timer_for_stage/2`
- Call helper from both `handle_params` and `handle_info({:update, ...})`
- Ensure timer appears on initial load AND refreshes

---

## 🟡 High Priority (Should Fix)

### 5. Singleton Anti-Pattern - Only One Game Allowed
**Status**: ❌ Not Fixed
**Location**: `lib/resistance/game.ex:37`, `lib/resistance/pregame.ex:7`
**Severity**: High - Cannot scale

**Problem**: Using `name: __MODULE__` means only ONE game can run on the entire server. Can't support multiple concurrent lobbies.

**Fix Required**:
- Add `Registry` for process naming
- Add `DynamicSupervisor` for spawning games
- Use `{:via, Registry, {Resistance.GameRegistry, game_id}}`
- Generate unique game_id per lobby

---

### 6. Inefficient Player List - O(n) Lookups
**Status**: ❌ Not Fixed
**Location**: `lib/resistance/game.ex:28`
**Severity**: High - Performance (minor for 5 players, but bad practice)

**Problem**: Using a List for players requires O(n) iteration for every lookup/update.

**Current**: `players: [Player]`
**Better**: `players: %{player_id => %Player{}}`

**Impact**: Every find_king, vote lookup, player update iterates the full list

---

### 7. Missing Input Validation - Vote Injection Possible
**Status**: ❌ Not Fixed
**Location**: `lib/resistance/game.ex:166, 174`
**Severity**: High - Security vulnerability

**Problem**: Vote handlers don't validate:
- If player_id is actually in the game
- If voter is on the quest team (for mission votes)
- Malicious client could inject fake votes

**Fix Required**:
- Validate player exists before accepting vote
- Validate player is on quest before accepting mission vote
- Log suspicious activity

---

### 8. Improper Supervision - Pregame Acts as Supervisor
**Status**: ❌ Not Fixed
**Location**: `lib/resistance/pregame.ex:131`
**Severity**: High - Fragile error handling

**Problem**: Pregame.Server directly spawns Game.Server instead of using proper OTP supervision.

**Current**:
```elixir
Game.Server.start_link(state)  # ⚠️ Wrong! Direct spawn
```

**Better**: Use DynamicSupervisor to spawn games

---

## 🟢 Medium Priority (Nice to Have)

### 9. Player Struct in Wrong File
**Status**: ❌ Not Fixed
**Location**: `lib/resistance/game.ex:1-18`
**Severity**: Low - Code organization

**Fix**: Move to `lib/resistance/player.ex`

---

### 10. Magic Numbers Scattered Throughout
**Status**: ❌ Not Fixed
**Locations**: Timer values (3000, 5000, 15000) hardcoded
**Severity**: Low - Maintainability

**Fix**: Use module attributes or config:
```elixir
@stage_timeouts %{
  init: 3_000,
  party_assembling: 15_000,
  voting: 15_000,
  quest: 15_000,
  quest_reveal: 5_000
}
```

---

### 11. Business Logic Mixed with GenServer Code
**Status**: ❌ Not Fixed
**Severity**: Low - Testability

**Fix**: Extract to `lib/resistance/game_logic.ex`:
- `check_win_condition/1`
- `assign_roles/1`
- `validate_team_size/2`
- etc.

---

### 12. CSRF Token as Player ID is Fragile
**Status**: ❌ Not Fixed
**Location**: All LiveViews use `session["_csrf_token"]`
**Severity**: Low - Identity management

**Problem**: CSRF tokens can rotate, aren't designed for persistent identity

**Fix**: Generate UUID in session:
```elixir
player_id = session["player_id"] || UUID.uuid4()
```

---

### 13. Typo in Victory Message
**Status**: ✅ FIXED
**Location**: `lib/resistance/game.ex:201`
**Severity**: Very Low - User-facing typo

**Current**: `"Morded wins!"`
**Should be**: `"Mordred wins!"`

---

### 14. No Rate Limiting
**Status**: ❌ Not Fixed
**Severity**: Low - DoS potential

**Problem**: Players could spam votes, chat messages, or ready toggles

**Fix**: Add rate limiting with `:hammer` or similar library

---

## Implementation Priority

**Phase 1 - Critical (Immediate)**: ✅ COMPLETED
1. ✅ Fix Pregame timer race condition
2. ✅ Make voting event-driven (advance on last vote)
3. ✅ Fix LiveView timer nil crashes
4. ✅ Fix LiveView refresh timer bug
5. ✅ BONUS: Fix typo (Morded → Mordred)

**Phase 2 - High Priority (Soon)**:
5. Add Registry + DynamicSupervisor (enables multiple games)
6. Change player list to map
7. Add vote validation
8. Fix supervision tree

**Phase 3 - Polish (Eventually)**:
9. Reorganize files
10. Extract magic numbers
11. Extract business logic
12. Use UUID for player IDs
13. Fix typo
14. Add rate limiting

---

## Notes

- **Breaking Changes**: Issues #5, #6 require significant refactoring
- **Quick Wins**: Issues #3, #13 are simple one-line fixes
- **User Impact**: Issues #2, #4 directly affect gameplay experience
- **Security**: Issue #7 is a potential exploit vector

---

## Testing Checklist

After implementing fixes, verify:
- [ ] Game doesn't start if player un-readies during countdown
- [ ] Game advances immediately when all votes are in
- [ ] No crashes when refreshing page
- [ ] Timer appears correctly after page refresh
- [ ] Invalid votes are rejected
- [ ] Multiple simultaneous games work (after #5)
