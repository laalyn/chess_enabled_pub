defmodule ChessEnabled.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      ChessEnabled.Repo,
      # Start the Telemetry supervisor
      ChessEnabledWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: ChessEnabled.PubSub, adapter: Phoenix.PubSub.Redis, host: "localhost", port: 6379, node_name: System.get_env("NODE")},
      # {Phoenix.PubSub, name: ChessEnabled.PubSub, adapter: Phoenix.PubSub.PG2},
      # Start the Endpoint (http/https)
      ChessEnabledWeb.Endpoint
      # Start a worker by calling: ChessEnabled.Worker.start_link(arg)
      # {ChessEnabled.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ChessEnabled.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    ChessEnabledWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
