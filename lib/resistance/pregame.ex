defmodule Pregame.Server do
  require Logger
  use GenServer

  alias Resistance.RoomCode

  @inactivity_timeout :timer.minutes(3)

  # Client API - Room Management

  # Child spec for DynamicSupervisor
  # Uses :transient restart - only restart on abnormal exits, not normal shutdowns
  def child_spec(room_code) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [room_code]},
      restart: :transient,
      type: :worker
    }
  end

  @doc """
  Starts a new pregame server for the given room code.
  Returns {:ok, pid} or {:error, reason}.
  """
  def start_link(room_code) do
    Logger.info("Starting Pregame.Server for room #{room_code}...")
    GenServer.start_link(
      __MODULE__,
      room_code,
      name: via_tuple(room_code)
    )
  end

  @doc """
  Finds or creates a pregame server for the given room code.
  Returns {:ok, pid}.
  """
  def find_or_create(room_code) do
    case find(room_code) do
      {:ok, pid} ->
        {:ok, pid}

      :error ->
        case DynamicSupervisor.start_child(
               Resistance.RoomSupervisor,
               {__MODULE__, room_code}
             ) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          error -> error
        end
    end
  end

  @doc """
  Finds an existing pregame server for the given room code.
  Returns {:ok, pid} or :error.
  """
  def find(room_code) do
    case Registry.lookup(Resistance.RoomRegistry, RoomCode.pregame_key(room_code)) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc """
  Checks if a room exists.
  """
  def room_exists?(room_code) do
    case find(room_code) do
      {:ok, _} -> true
      :error -> false
    end
  end

  # Client API - Player Management

  @doc """
  Adds a player to the pregame lobby and broadcasts the update.
  Returns :ok if successful,
  :lobby_full if the lobby is full,
  or {:error, reason} if player's name is invalid.
  """
  def add_player(room_code, id, name) do
    with {:ok, _pid} <- find_or_create(room_code) do
      GenServer.call(via_tuple(room_code), {:add_player, id, name})
    end
  end

  @doc """
  Returns true if the player is in the pregame lobby.
  """
  def is_player(room_code, id) do
    case find(room_code) do
      {:ok, _} -> GenServer.call(via_tuple(room_code), {:is_player, id})
      :error -> false
    end
  end

  @doc """
  Returns a map of player ids to {name, ready} tuples.
  """
  def get_players(room_code) do
    case find(room_code) do
      {:ok, _} -> GenServer.call(via_tuple(room_code), :get_players)
      :error -> %{}
    end
  end

  @doc """
  Removes a player from the pregame lobby and broadcasts the update.
  """
  def remove_player(room_code, id) do
    case find(room_code) do
      {:ok, _} -> GenServer.cast(via_tuple(room_code), {:remove_player, id})
      :error -> :ok
    end
  end

  @doc """
  Provide a subscription API to the pregame lobby.
  """
  def subscribe(room_code) do
    Phoenix.PubSub.subscribe(Resistance.PubSub, RoomCode.pubsub_topic(room_code))
  end

  @doc """
  Toggles a player's ready status and broadcasts the update.
  If all players are ready, starts the game in 5 seconds.
  """
  def toggle_ready(room_code, id) do
    case find(room_code) do
      {:ok, _} -> GenServer.cast(via_tuple(room_code), {:toggle_ready, id})
      :error -> :ok
    end
  end

  @doc """
  Returns :ok if the name is valid,
  or {:error, reason} if the name is invalid.
  """
  def validate_name(room_code, name) do
    case find(room_code) do
      {:ok, _} -> GenServer.call(via_tuple(room_code), {:validate_name, name})
      :error -> :ok
    end
  end

  # GenServer Callbacks

  @impl true
  def init(room_code) do
    Process.flag(:trap_exit, true)

    # Start inactivity timer
    inactivity_timer = Process.send_after(self(), :check_inactivity, @inactivity_timeout)

    {:ok,
     %{
       room_code: room_code,
       players: %{},
       timer_ref: nil,
       inactivity_timer: inactivity_timer,
       last_activity: System.monotonic_time(:millisecond)
     }}
  end

  @impl true
  def handle_cast({:remove_player, id}, state) do
    # Cancel timer if a player leaves
    if state.timer_ref, do: :timer.cancel(state.timer_ref)

    new_players = Map.delete(state.players, id)
    new_state = %{
      state
      | players: new_players,
        timer_ref: nil,
        last_activity: System.monotonic_time(:millisecond)
    }

    broadcast(state.room_code, :update, new_players)

    # If no players left, start inactivity timer
    new_state = if map_size(new_players) == 0 do
      Logger.info("Room #{state.room_code}: All players left, will shutdown in 3 minutes if empty")
      # Cancel existing inactivity timer if any
      if new_state.inactivity_timer, do: Process.cancel_timer(new_state.inactivity_timer)
      inactivity_timer = Process.send_after(self(), :check_inactivity, @inactivity_timeout)
      %{new_state | inactivity_timer: inactivity_timer}
    else
      new_state
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:toggle_ready, id}, state) do
    case Map.get(state.players, id) do
      nil ->
        {:noreply, state}

      {name, ready} ->
        # Cancel existing timer when state changes
        if state.timer_ref, do: :timer.cancel(state.timer_ref)

        new_players = Map.put(state.players, id, {name, !ready})

        # Check if all players are ready
        all_ready =
          Enum.count(new_players) == max_players() &&
            Enum.all?(new_players, fn {_, {_, ready}} -> ready end)

        new_state =
          case all_ready do
            true ->
              broadcast(state.room_code, :start_timer, new_players)
              {:ok, timer_ref} = :timer.send_after(5000, self(), :start_game)

              %{
                state
                | players: new_players,
                  timer_ref: timer_ref,
                  last_activity: System.monotonic_time(:millisecond)
              }

            _ ->
              broadcast(state.room_code, :update, new_players)

              %{
                state
                | players: new_players,
                  timer_ref: nil,
                  last_activity: System.monotonic_time(:millisecond)
              }
          end

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_call({:add_player, id, name}, _from, state) do
    cond do
      valid_name(name, state.players) != :ok ->
        {:reply, valid_name(name, state.players), state}

      Enum.count(state.players) == max_players() ->
        {:reply, :lobby_full, state}

      Game.Server.room_exists?(state.room_code) ->
        {:reply, :game_in_progress, state}

      true ->
        new_players = Map.put(state.players, id, {name, false})

        # Cancel inactivity timer if room was empty and now has players
        new_state = if map_size(state.players) == 0 && state.inactivity_timer do
          Process.cancel_timer(state.inactivity_timer)
          %{state | inactivity_timer: nil}
        else
          state
        end

        new_state = %{
          new_state
          | players: new_players,
            last_activity: System.monotonic_time(:millisecond)
        }

        broadcast(state.room_code, :update, new_players)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:get_players, _from, state) do
    {:reply, state.players, state}
  end

  @impl true
  def handle_call({:is_player, id}, _from, state) do
    {:reply, Map.get(state.players, id) != nil, state}
  end

  @impl true
  def handle_call({:validate_name, name}, _from, state) do
    {:reply, valid_name(name, state.players), state}
  end

  # start the Game.Server if all players are ready
  @impl true
  def handle_info(:start_game, state) do
    # Verify BOTH count AND ready status before starting
    all_ready =
      Enum.count(state.players) == max_players() &&
        Enum.all?(state.players, fn {_, {_, ready}} -> ready end)

    if all_ready do
      case Game.Server.start_link(state.room_code, state.players) do
        {:ok, _pid} ->
          Resistance.Analytics.increment_stat("games_started")
          :ok
        {:error, reason} ->
          Logger.error("Failed to start game: #{inspect(reason)}")
          broadcast(state.room_code, :error, "Failed to start game")
      end
    end


    {:noreply, %{state | timer_ref: nil}}
  end

  # reset the state when Game ends
  @impl true
  def handle_info({:EXIT, _from, _reason}, state) do
    Logger.log(:info, "Room #{state.room_code}: Game ended, resetting pregame state")

    {:noreply,
     %{
       state
       | players: %{},
         timer_ref: nil,
         last_activity: System.monotonic_time(:millisecond)
     }}
  end

  # Check for inactivity and shutdown if room is empty
  @impl true
  def handle_info(:check_inactivity, state) do
    if map_size(state.players) == 0 do
      time_since_activity =
        System.monotonic_time(:millisecond) - state.last_activity

      if time_since_activity >= @inactivity_timeout do
        Logger.info("Room #{state.room_code}: Shutting down due to inactivity")
        {:stop, :normal, state}
      else
        # Calculate remaining time and reschedule
        remaining_time = @inactivity_timeout - time_since_activity
        inactivity_timer = Process.send_after(self(), :check_inactivity, remaining_time)
        {:noreply, %{state | inactivity_timer: inactivity_timer}}
      end
    else
      # Players present, don't reschedule - will be rescheduled when room becomes empty
      {:noreply, %{state | inactivity_timer: nil}}
    end
  end

  @impl true
  def terminate(_reason, state) do
    # Clean up timers on termination
    if state.timer_ref, do: :timer.cancel(state.timer_ref)
    if state.inactivity_timer, do: Process.cancel_timer(state.inactivity_timer)
    :ok
  end

  # Helper Functions

  defp via_tuple(room_code) do
    {:via, Registry, {Resistance.RoomRegistry, RoomCode.pregame_key(room_code)}}
  end

  defp broadcast(room_code, event, payload) do
    Phoenix.PubSub.broadcast(
      Resistance.PubSub,
      RoomCode.pubsub_topic(room_code),
      {event, payload}
    )
  end

  defp valid_name(name, players) do
    cond do
      name_taken(name, players) ->
        {:error, "Name is already taken."}

      !Regex.match?(~r/^[a-zA-Z0-9_ ]+$/, name) ->
        {:error, "Name can only contain letters, numbers, spaces, and underscores."}

      !Regex.match?(~r/^.{4,12}$/, name) ->
        {:error, "Name must be between 4-12 characters long."}

      true ->
        :ok
    end
  end

  defp name_taken(name, players) do
    players
    |> Map.values()
    |> Enum.any?(fn {n, _} -> n == name end)
  end

  def max_players(), do: 5
end
