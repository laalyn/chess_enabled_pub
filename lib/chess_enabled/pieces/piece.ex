defmodule ChessEnabled.Pieces.Piece do
  use Ecto.Schema
  import Ecto.Changeset

  alias ChessEnabled.Matches.Match

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  schema "pieces" do
    field :type, :string
    belongs_to :match, Match

    timestamps()
  end
end
