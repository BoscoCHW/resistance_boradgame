defmodule Pregame.Server do
  require Logger
  use GenServer

  def start_link(_) do
    Logger.info("Starting Pregame.Server...")
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # Client API

  @doc """
    Adds a player to the pregame lobby and broadcasts the update.
    Returns :ok if successful,
    :lobby_full if the lobby is full,
    or {:error, reason} if player's name is invalid.
  """
  def add_player(id, name) do
    GenServer.call(__MODULE__, {:add_player, id, name})
  end

  @doc """
    Returns true if the player is in the pregame lobby.
  """
  def is_player(id) do
    GenServer.call(__MODULE__, {:is_player, id})
  end

  @doc """
    Returns a map of player ids to {name, ready} tuples.
  """
  def get_players() do
    GenServer.call(__MODULE__, :get_players)
  end

  @doc """
    Removes a player from the pregame lobby and broadcasts the update.
  """
  def remove_player(id) do
    GenServer.cast(__MODULE__, {:remove_player, id})
  end

  @doc """
    provide a subscription API to the pregame lobby.
  """
  def subscribe() do
    Phoenix.PubSub.subscribe(Resistance.PubSub, "pregame")
  end

  @doc """
    Toggles a player's ready status and broadcasts the update.
    If all players are ready, starts the game in 5 seconds.
  """
  def toggle_ready(id) do
    GenServer.cast(__MODULE__, {:toggle_ready, id})
  end

  @doc """
    Returns :ok if the name is valid,
    or {:error, reason} if the name is invalid.
  """
  def validate_name(name) do
    GenServer.call(__MODULE__, {:validate_name, name})
  end

  @impl true
  def init(_) do
    Process.flag(:trap_exit, true)
    {:ok, %{players: %{}, timer_ref: nil}}
  end

  @impl true
  def handle_cast({:remove_player, id}, state) do
    # Cancel timer if a player leaves
    if state.timer_ref, do: :timer.cancel(state.timer_ref)

    new_players = Map.delete(state.players, id)
    new_state = %{state | players: new_players, timer_ref: nil}
    broadcast(:update, new_players)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:toggle_ready, id}, state) do
    case Map.get(state.players, id) do
      nil -> {:noreply, state}
      {name, ready} ->
        # Cancel existing timer when state changes
        if state.timer_ref, do: :timer.cancel(state.timer_ref)

        new_players = Map.put(state.players, id, {name, !ready})

        # Check if all players are ready
        all_ready = Enum.count(new_players) == max_players()
          && Enum.all?(new_players, fn {_, {_, ready}} -> ready end)

        case all_ready do
          true ->
            broadcast(:start_timer, new_players)
            {:ok, timer_ref} = :timer.send_after(5000, self(), :start_game)
            {:noreply, %{state | players: new_players, timer_ref: timer_ref}}
          _ ->
            broadcast(:update, new_players)
            {:noreply, %{state | players: new_players, timer_ref: nil}}
        end
    end
  end

  @impl true
  def handle_call({:add_player, id, name}, _from, state) do
    cond do
      valid_name(name, state.players) != :ok ->
        {:reply, valid_name(name, state.players), state}
      Enum.count(state.players) == max_players() ->
        {:reply, :lobby_full, state}
      GenServer.whereis(Game.Server) != nil ->
        {:reply, :game_in_progress, state}
      true ->
        new_players = Map.put(state.players, id, {name, false})
        new_state = %{state | players: new_players}
        broadcast(:update, new_players)
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
    all_ready = Enum.count(state.players) == max_players() &&
                Enum.all?(state.players, fn {_, {_, ready}} -> ready end)

    if all_ready do
      Game.Server.start_link(state.players)
    end

    {:noreply, %{state | timer_ref: nil}}
  end

  # reset the state when Game ends
  @impl true
  def handle_info({:EXIT, _from, _reason}, _) do
    Logger.log(:info, "Reseting Pregame.Server state")
    {:noreply, %{players: %{}, timer_ref: nil}}
  end



  # Helper Functions

  defp broadcast(event, payload) do
    Phoenix.PubSub.broadcast(Resistance.PubSub, "pregame", {event, payload})
  end

  defp valid_name(name, players) do
    cond do
      name_taken(name, players) -> {:error, "Name is already taken."}
      !Regex.match?(~r/^[a-zA-Z0-9_]+$/, name) -> {:error, "Name can only contain letters, numbers, and underscores."}
      !Regex.match?(~r/^.{4,12}$/, name) -> {:error, "Name must be between 4-12 characters long."}
      true -> :ok
    end
  end

  defp name_taken(name, players) do
    players
    |> Map.values()
    |> Enum.any?(fn {n, _} -> n == name end)
  end

  def max_players(), do: 2
end
