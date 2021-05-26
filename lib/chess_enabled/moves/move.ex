defmodule ChessEnabled.Moves.Move do
  use Ecto.Schema
  import Ecto.Changeset

  alias ChessEnabled.Players.Player
  alias ChessEnabled.Pieces.Piece

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  schema "moves" do
    field :idx, :integer
    field :row, :integer
    field :col, :integer
    belongs_to :player, Player
    belongs_to :piece, Piece

    timestamps()
  end
end
