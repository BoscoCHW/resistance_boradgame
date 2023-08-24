defmodule Pregame.Server do
  require Logger
  use GenServer, restart: :transient

  def start_link(server_id) do
    Logger.info("Starting Pregame.Server #{server_id}...")
    GenServer.start_link(__MODULE__, {server_id, %{}}, name: via(server_id))
  end

  # Client API

  @doc """
    Adds a player to the pregame lobby and broadcasts the update.
    Returns :ok if successful,
    :lobby_full if the lobby is full,
    or {:error, reason} if player's name is invalid.
  """
  def add_player(server_id, id, name) do
    GenServer.call(via(server_id), {:add_player, id, name})
  end

  @doc """
    Returns true if the player is in the pregame lobby.
  """
  def is_player(server_id, id) do
    GenServer.call(via(server_id), {:is_player, id})
  end

  @doc """
    Returns a map of player ids to {name, ready} tuples.
  """
  def get_players(server_id) do
    GenServer.call(via(server_id), :get_players)
  end

  @doc """
    Removes a player from the pregame lobby and broadcasts the update.
  """
  def remove_player(server_id, id) do
    GenServer.cast(via(server_id), {:remove_player, id})
  end

  @doc """
    provide a subscription API to the pregame lobby.
  """
  def subscribe(server_id) do
    Phoenix.PubSub.subscribe(Resistance.PubSub, "pregame-#{server_id}")
  end

  @doc """
    Toggles a player's ready status and broadcasts the update.
    If all players are ready, starts the game in 5 seconds.
  """
  def toggle_ready(server_id, id) do
    GenServer.cast(via(server_id), {:toggle_ready, id})
  end

  @doc """
    Returns :ok if the name is valid,
    or {:error, reason} if the name is invalid.
  """
  def validate_name(server_id, name) do
    GenServer.call(via(server_id), {:validate_name, name})
  end

  @doc """
    state is a map of
    %{
      id => {name, readied}
    }
  """
  @impl true
  def init(state) do
    Process.flag(:trap_exit, true)
    {:ok, state}
  end

  @impl true
  def handle_cast({:remove_player, id}, {server_id, state}) do
    new_state = Map.delete(state, id)
    broadcast(:update, new_state)
    {:noreply, {server_id, new_state}}
  end

  @impl true
  def handle_cast({:toggle_ready, id}, {server_id, state}) do
    case Map.get(state, id) do
      nil -> {:noreply, {server_id, state}}
      {name, ready} ->
        new_state = Map.put(state, id, {name, !ready})
        case Enum.count(new_state) == max_players()
          && Enum.all?(new_state, fn {_, {_, ready}} -> ready end) do
          true ->
            broadcast(:start_timer, new_state)
            :timer.send_after(5000, self(), :start_game)
          _ -> broadcast(:update, new_state)
        end
        {:noreply, {server_id, new_state}}
    end
  end

  @impl true
  def handle_call({:add_player, id, name}, _from, {server_id, state}) do
    cond do
      valid_name(name, state) != :ok ->
        {:reply, valid_name(name, state), {server_id, state}}
      Enum.count(state) == max_players() ->
        {:reply, :lobby_full, state}
      GenServer.whereis(Game.Server) != nil ->
        {:reply, :game_in_progress, {server_id, state}}
      true ->
        new_state = Map.put(state, id, {name, false})
        broadcast(:update, new_state)
        {:reply, :ok, {server_id, new_state}}
    end
  end

  @impl true
  def handle_call(:get_players, _from, {server_id, state}) do
    {:reply, state, {server_id, state}}
  end

  @impl true
  def handle_call({:is_player, id}, _from, {server_id, state}) do
    {:reply, Map.get(state, id) != nil, {server_id, state}}
  end

  @impl true
  def handle_call({:validate_name, name}, _from, {server_id, state}) do
    {:reply, valid_name(name, state), {server_id, state}}
  end

  # start the Game.Server if all players are ready
  @impl true
  def handle_info(:start_game, {server_id, state}) do
    if Enum.count(state) == max_players() do
      Game.Server.start_link(state)
    end
    {:noreply, {server_id, state}}
  end

  # reset the state when Game ends
  @impl true
  def handle_info({:EXIT, f, r}, _) do
    IO.inspect(f)
    IO.inspect(r)
    Logger.log(:info, "Reseting Pregame.Server state")
    {:noreply, %{}}
  end



  # Helper Functions

  defp broadcast(server_id, event, payload) do
    Phoenix.PubSub.broadcast(Resistance.PubSub, "pregame-#{server_id}", {event, payload})
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

  defp via(server_id) do
    {:via, Registry, {AvalonRegistry, {__MODULE__, server_id}}}
  end

  def max_players(), do: 1
end
