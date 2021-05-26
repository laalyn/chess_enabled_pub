defmodule ChessEnabled.Matches.Match do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  schema "matches" do
    field :type, :string
    field :closed, :boolean
    field :next_idx, :integer

    timestamps()
  end
end
