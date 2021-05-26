defmodule ChessEnabled.Players.Player do
  use Ecto.Schema
  import Ecto.Changeset

  alias ChessEnabled.Accounts.User
  alias ChessEnabled.Matches.Match

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  schema "players" do
    field :idx, :integer
    field :status, :string
    field :elo_delta, :integer
    belongs_to :user, User
    belongs_to :match, Match

    timestamps()
  end
end
