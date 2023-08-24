defmodule Resistance.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      ResistanceWeb.Telemetry,
      # Start the Ecto repository
      Resistance.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: Resistance.PubSub},
      # Start Finch
      {Finch, name: Resistance.Finch},
      # Start the Endpoint (http/https)
      ResistanceWeb.Endpoint,
      Avalon.Supervisor,
      {Registry, [name: AvalonRegistry, keys: :unique]},
      # Start a worker by calling: Resistance.Worker.start_link(arg)
      # {Resistance.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    :ets.new(:pregame_states, [:named_table, :public])
    opts = [strategy: :one_for_one, name: Resistance.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ResistanceWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
