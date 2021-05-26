defmodule ChessEnabled.Repo do
  use Ecto.Repo,
    otp_app: :chess_enabled,
    adapter: Ecto.Adapters.Postgres
end
