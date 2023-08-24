defmodule Avalon.Supervisor do
  use DynamicSupervisor

  def start_link(_) do
    IO.puts("Avalon.Supervisor starting...")
    DynamicSupervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_pregame(id) do
    DynamicSupervisor.start_child(
      __MODULE__,               # supervisor
      {Pregame.Server, id}
    )
  end

  def start_game(id) do
    DynamicSupervisor.start_child(
      __MODULE__,               # supervisor
      {Game.Server, id}
    )
  end

end
