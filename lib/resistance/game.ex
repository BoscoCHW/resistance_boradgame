defmodule Player do
  defstruct [
    # player id
    :id,
    # player name
    :name,
    # :good | :bad
    :role,
    # bool
    :is_king,
    # bool
    :on_quest
  ]

  def new(id, name, role, is_king \\ false, on_quest \\ false) do
    %Player{id: id, name: name, role: role, is_king: is_king, on_quest: on_quest}
  end

  def become_king(player) do
    %{player | is_king: true}
  end
end

defmodule Game.Server do
  use GenServer
  require Logger

  alias Resistance.RoomCode

  @quest_config %{1 => 2, 2 => 3, 3 => 2, 4 => 3, 5 => 3}

  # Store game state. The state is a map with the following keys:
  #     room_code: string, # the room code for this game
  #     players: [Player], # a list of Player, order never change during the game
  #     quest_outcomes: [:success | :fail],     # a list of quest outcomes
  #     stage: :init | :party_assembling | :voting | :quest | :quest_reveal | :end_game # current stage of the game
  #     team_votes: %{player_id => :approve | :reject},      # a map of player's vote for the current team
  #     quest_votes: %{player_id => :assist | :sabotage}      # a map of team members vote for the current quest
  #     team_rejection_count: int

  # Client API - Room Management

  @doc """
  Child spec for DynamicSupervisor.
  Uses :transient restart - only restart on abnormal exits, not normal shutdowns.
  """
  def child_spec({room_code, pregame_state}) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [room_code, pregame_state]},
      restart: :transient,
      type: :worker
    }
  end

  def start_link(room_code, pregame_state) do
    Logger.info("Starting Game.Server for room #{room_code}...")
    GenServer.start_link(__MODULE__, {room_code, pregame_state}, name: via_tuple(room_code))
  end

  @doc """
  Finds an existing game server for the given room code.
  Returns {:ok, pid} or :error.
  """
  def find(room_code) do
    case Registry.lookup(Resistance.RoomRegistry, RoomCode.game_key(room_code)) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc """
  Checks if a game exists for the given room.
  """
  def room_exists?(room_code) do
    case find(room_code) do
      {:ok, _} -> true
      :error -> false
    end
  end

  # Client API - Game Actions

  @doc """
    get players in the game
  """
  def get_state(room_code) do
    case find(room_code) do
      {:ok, _} -> GenServer.call(via_tuple(room_code), :get_state)
      :error -> nil
    end
  end

  @doc """
    check if player is in the game
  """
  def is_player(room_code, id) do
    case find(room_code) do
      {:ok, _} -> GenServer.call(via_tuple(room_code), {:is_player, id})
      :error -> false
    end
  end

  @doc """
    toggle selected player's on_quest status
  """
  def toggle_quest_member(room_code, king_id, player_id) do
    case find(room_code) do
      {:ok, _} -> GenServer.call(via_tuple(room_code), {:toggle_quest_member, king_id, player_id})
      :error -> {:error, "Game not found"}
    end
  end

  @doc """
    add a player's vote to the current vote list. If everyone has voted, broadcast if the team is approved or not
  """
  def vote_for_team(room_code, player_id, vote) do
    case find(room_code) do
      {:ok, _} -> GenServer.cast(via_tuple(room_code), {:vote_for_team, player_id, vote})
      :error -> :ok
    end
  end

  @doc """
    menbers of the current team vote for the mission. If everyone has voted, broadcast if the mission is successful or not
  """
  def vote_for_mission(room_code, player_id, vote) do
    case find(room_code) do
      {:ok, _} -> GenServer.cast(via_tuple(room_code), {:vote_for_mission, player_id, vote})
      :error -> :ok
    end
  end

  @doc """
    player broadcasts a message to all players
  """
  def message(room_code, player_id, msg) do
    case find(room_code) do
      {:ok, _} -> GenServer.cast(via_tuple(room_code), {:message, player_id, msg})
      :error -> :ok
    end
  end

  def remove_player(room_code, player_id) do
    case find(room_code) do
      {:ok, _} -> GenServer.cast(via_tuple(room_code), {:remove_player, player_id})
      :error -> :ok
    end
  end

  ### subscribe and broadcast functions
  def subscribe(room_code) do
    Phoenix.PubSub.subscribe(Resistance.PubSub, RoomCode.pubsub_topic(room_code))
  end

  # get max number of players for a quest
  def max_quest_members(round) do
    Map.get(@quest_config, round, 3)
  end

  @impl true
  def init({room_code, pregame_state}) do
    id_n_names =
      Enum.reduce(pregame_state, [], fn {player_id, {name, _}}, acc ->
        [{player_id, name} | acc]
      end)

    players = make_players(id_n_names)

    state = %{
      # room code for this game
      room_code: room_code,
      # a list of Player, order never change during the game
      players: players,
      # [:success | :fail]   #current_mission = length(mission_results) + 1
      quest_outcomes: [],
      # :init | :party_assembling | :voting | :quest | :quest_reveal | :end_game
      stage: :init,
      # %{player_id => :approve | :reject}
      team_votes: %{},
      # %{player_id => :assist | :sabotage}
      # initial stage is :approve for all players
      quest_votes: %{},
      team_rejection_count: 0,
      winning_team: nil,
      # timer reference for current stage
      timer_ref: nil
    }

    {:ok, timer_ref} = :timer.send_after(3000, self(), {:end_stage, :init})
    {:ok, %{state | timer_ref: timer_ref}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:is_player, id}, _from, state) do
    {:reply, Enum.any?(state.players, fn p -> p.id == id end), state}
  end

  @impl true
  def handle_call({:toggle_quest_member, king_id, player_id}, _from, state) do
    cond do
      find_king(state.players).id != king_id ->
        {:reply, {:error, "You are not the king"}, state}

      is_team_full(state.players, player_id, get_round(state)) ->
        # 3 players already on quest and player_id is not one of them
        {:reply, {:error, "The team is full"}, state}

      true ->
        updated_players =
          Enum.map(state.players, fn player ->
            if player.id == player_id do
              prev_on_quest = player.on_quest
              %Player{player | on_quest: !prev_on_quest}
            else
              player
            end
          end)

        new_state = %{state | players: updated_players}
        broadcast(state.room_code, :update, new_state)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_cast({:vote_for_team, player_id, vote}, state) do
    updated_team_votes = Map.put(state.team_votes, player_id, vote)
    new_state = %{state | team_votes: updated_team_votes}
    broadcast(state.room_code, :update, new_state)

    # Check if all players have voted - advance immediately
    if map_size(updated_team_votes) == length(state.players) do
      if new_state.timer_ref, do: Process.cancel_timer(new_state.timer_ref)
      send(self(), {:end_stage, :voting})
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:vote_for_mission, player_id, vote}, state) do
    updated_quest_votes = Map.put(state.quest_votes, player_id, vote)
    new_state = %{state | quest_votes: updated_quest_votes}
    broadcast(state.room_code, :update, new_state)

    # Check if all quest members have voted - advance immediately
    quest_member_count = Enum.count(state.players, fn p -> p.on_quest end)
    if map_size(updated_quest_votes) == quest_member_count do
      if new_state.timer_ref, do: Process.cancel_timer(new_state.timer_ref)
      send(self(), {:end_stage, :quest})
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:remove_player, player_id}, state) do
    updated_players = Enum.filter(state.players, fn player -> player.id != player_id end)
    updated_team_votes = Map.delete(state.team_votes, player_id)
    updated_quest_votes = Map.delete(state.quest_votes, player_id)

    new_state = %{
      state
      | players: updated_players,
        team_votes: updated_team_votes,
        quest_votes: updated_quest_votes
    }

    num_bad_guys = Enum.count(updated_players, fn player -> player.role == :bad end)
    num_good_guys = Enum.count(updated_players, fn player -> player.role == :good end)

    new_state =
      cond do
        num_bad_guys > num_good_guys ->
          %{new_state | stage: :end_game, winning_team: :bad}
          broadcast(state.room_code, :message, "Mordred wins!")
          broadcast(state.room_code, :update, new_state)
          end_game(state.room_code)

        num_bad_guys == 0 ->
          %{new_state | stage: :end_game, winning_team: :good}
          broadcast(state.room_code, :message, "Arthur wins!")
          broadcast(state.room_code, :update, new_state)
          end_game(state.room_code)

        true ->
          new_state
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:message, player_id, msg}, state) do
    sender = Enum.find(state.players, fn player -> player.id == player_id end)
    broadcast(state.room_code, :message, {:user, "#{sender.name}: #{msg}"})
    {:noreply, state}
  end

  @impl true
  def handle_info({:end_stage, stage}, state) do
    case stage do
      :init ->
        broadcast(state.room_code, :update, state)
        {:noreply, party_assembling_stage(state)}

      :party_assembling ->
        if Enum.count(state.players, fn x -> x.on_quest end) ==
             max_quest_members(get_round(state)) do
          {:noreply, voting_stage(state)}
        else
          {:noreply, clean_up(state)}
        end

      :voting ->
        if check_team_approved(state.team_votes) do
          {:noreply, quest_stage(state)}
        else
          {:noreply, clean_up(state)}
        end

      :quest ->
        default_votes =
          state.players
          |> Enum.filter(fn p -> p.on_quest && state.quest_votes[p.id] == nil end)
          |> Enum.map(fn p -> {p.id, :assist} end)
          |> Map.new()

        updated_quest_votes = Map.merge(state.quest_votes, default_votes)
        new_state = %{state | quest_votes: updated_quest_votes}
        {:noreply, quest_reveal_stage(new_state)}

      :quest_reveal ->
        {:noreply, clean_up(state)}
    end
  end

  # return a list of players, with 1/3 of them being bad and the rest being good
  defp make_players(ids_n_names) do
    num_bad = (length(ids_n_names) / 3) |> Float.ceil() |> round
    num_good = length(ids_n_names) - num_bad
    roles = Enum.shuffle(List.duplicate(:good, num_good) ++ List.duplicate(:bad, num_bad))

    Enum.zip_with(ids_n_names, roles, fn {id, name}, role ->
      Player.new(id, name, role)
    end)
  end

  # assemble the party with a new king
  defp party_assembling_stage(state) do
    Logger.log(:info, "party_assembling_stage")
    # assign next king
    players = assign_next_king(state.players)
    new_state = %{state | stage: :party_assembling, players: players}
    new_king = find_king(new_state.players).name
    broadcast(state.room_code, :message, {:server, "#{new_king} is now king!"})
    broadcast(state.room_code, :update, new_state)
    {:ok, timer_ref} = :timer.send_after(15000, self(), {:end_stage, :party_assembling})
    %{new_state | timer_ref: timer_ref}
  end

  defp voting_stage(state) do
    Logger.log(:info, "voting_stage")

    new_state =
      state
      |> Map.put(:stage, :voting)

    broadcast(state.room_code, :update, new_state)
    {:ok, timer_ref} = :timer.send_after(15000, self(), {:end_stage, :voting})
    %{new_state | timer_ref: timer_ref}
  end

  defp quest_stage(state) do
    Logger.log(:info, "quest_stage")
    new_state = Map.put(state, :stage, :quest)
    broadcast(state.room_code, :update, new_state)
    {:ok, timer_ref} = :timer.send_after(15000, self(), {:end_stage, :quest})
    %{new_state | timer_ref: timer_ref}
  end

  defp quest_reveal_stage(state) do
    Logger.log(:info, "quest_reveal_stage")
    new_state = Map.put(state, :stage, :quest_reveal)
    broadcast(state.room_code, :update, new_state)
    {:ok, timer_ref} = :timer.send_after(15000, self(), {:end_stage, :quest_reveal})
    %{new_state | timer_ref: timer_ref}
  end

  # called after king selects team
  defp clean_up(%{stage: :party_assembling} = state) do
    Logger.log(:info, "clean_up")
    {:ok, timer_ref} = :timer.send_after(3000, self(), {:end_stage, :init})

    %{
      room_code: state.room_code,
      players:
        Enum.map(state.players, fn player ->
          %Player{player | on_quest: false}
        end),
      quest_outcomes: state.quest_outcomes,
      stage: :init,
      team_votes: %{},
      quest_votes: %{},
      team_rejection_count: state.team_rejection_count,
      winning_team: nil,
      timer_ref: timer_ref
    }
  end

  # called when quest team is rejected
  defp clean_up(%{stage: :voting} = state) do
    Logger.log(:info, "clean_up")

    if state.team_rejection_count >= 4 do
      broadcast(state.room_code, :message, {:server, "Bad guys win!"})
      broadcast(state.room_code, :update, %{state | stage: :end_game, winning_team: :bad})
      end_game(state.room_code)
    else
      {:ok, timer_ref} = :timer.send_after(3000, self(), {:end_stage, :init})

      %{
        room_code: state.room_code,
        players: Enum.map(state.players, fn player -> %Player{player | on_quest: false} end),
        quest_outcomes: state.quest_outcomes,
        stage: :init,
        team_votes: %{},
        quest_votes: %{},
        team_rejection_count: state.team_rejection_count + 1,
        winning_team: nil,
        timer_ref: timer_ref
      }
    end
  end

  # called when quest reveal stage finished
  defp clean_up(%{stage: :quest_reveal} = state) do
    Logger.log(:info, "clean_up")
    quest_result = get_result(state.quest_votes)
    new_quest_outcomes = state.quest_outcomes ++ [quest_result]

    case check_win_condition(new_quest_outcomes) do
      {:end_game, :bad} ->
        broadcast(state.room_code, :message, {:server, "Mordred wins!"})
        broadcast(state.room_code, :update, %{state | stage: :end_game, winning_team: :bad})
        end_game(state.room_code)

      {:end_game, :good} ->
        broadcast(state.room_code, :message, {:server, "Arthur wins!"})
        broadcast(state.room_code, :update, %{state | stage: :end_game, winning_team: :good})
        end_game(state.room_code)

      {:continue, _} ->
        {:ok, timer_ref} = :timer.send_after(3000, self(), {:end_stage, :init})

        %{
          room_code: state.room_code,
          players: Enum.map(state.players, fn player -> %Player{player | on_quest: false} end),
          quest_outcomes: new_quest_outcomes,
          stage: :init,
          team_votes: %{},
          quest_votes: %{},
          team_rejection_count: state.team_rejection_count,
          winning_team: nil,
          timer_ref: timer_ref
        }
    end
  end

  # check if bad guys or good guys have won
  defp check_win_condition(quest_outcomes) do
    num_fails = Enum.count(quest_outcomes, fn result -> result == :fail end)
    num_passes = Enum.count(quest_outcomes, fn result -> result == :succeed end)

    cond do
      num_fails >= 3 ->
        {:end_game, :bad}

      num_passes >= 3 ->
        {:end_game, :good}

      true ->
        {:continue, nil}
    end
  end

  # assign next king, return updated players
  defp assign_next_king(players) do
    king_idx =
      case Enum.find_index(players, fn player -> player.is_king end) do
        nil -> 0
        king_idx -> king_idx
      end

    next_king_idx = rem(king_idx + 1, length(players))

    Enum.map(players, fn player ->
      if player.name == Enum.at(players, next_king_idx).name do
        %{player | is_king: true}
      else
        %{player | is_king: false}
      end
    end)
  end

  # find king from players
  defp find_king(players) do
    Enum.find(players, fn player -> player.is_king end)
  end

  defp is_team_full(players, added_player_id, round) do
    Enum.count(players, fn player -> player.on_quest end) >= max_quest_members(round) &&
      Enum.any?(players, fn player ->
        player.id == added_player_id && !player.on_quest
      end)
  end

  # Helper Functions

  defp via_tuple(room_code) do
    {:via, Registry, {Resistance.RoomRegistry, RoomCode.game_key(room_code)}}
  end

  defp broadcast(room_code, event, payload) do
    Phoenix.PubSub.broadcast(
      Resistance.PubSub,
      RoomCode.pubsub_topic(room_code),
      {event, payload}
    )
  end

  # determines if the quest succeeded or failed
  defp get_result(quest_votes) do
    if Enum.all?(quest_votes, fn {_, vote} -> vote == :assist end) do
      :succeed
    else
      :fail
    end
  end

  # check if quest team is approved
  defp check_team_approved(team_votes) do
    votes = Map.values(team_votes)
    half = (length(votes) / 2) |> Float.floor() |> round
    Enum.count(votes, fn v -> v == :approve end) > half
  end

  # Terminate server when game ends
  defp end_game(room_code) do
    GenServer.stop(via_tuple(room_code))
  end

  # get current round
  defp get_round(state) do
    length(state.quest_outcomes) + 1
  end
end
