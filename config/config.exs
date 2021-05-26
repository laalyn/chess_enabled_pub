# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :chess_enabled,
  ecto_repos: [ChessEnabled.Repo],
  generators: [binary_id: true]

# Configures the endpoint
config :chess_enabled, ChessEnabledWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "UtCja/76fHyzdXekCfm2YNikv8KJqCQJASfestV7I0JtOlT7L6+xXAwVRENrDYA1",
  render_errors: [view: ChessEnabledWeb.ErrorView, accepts: ~w(json), layout: false],
  pubsub_server: ChessEnabled.PubSub,
  live_view: [signing_salt: "HYEQn7yU"]

# Guardian config
config :chess_enabled, ChessEnabled.Guardian,
  issuer: "chess_enabled",
  secret_key: "sXdSPAV87IFSvYDQaEkB9JWE7Dx0y47JkSKP+xNZD8L1WG5ME2NUCuyVDY5LC3FF"

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
