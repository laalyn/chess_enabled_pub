defmodule ChessEnabled.Queue.CC do
  use Ecto.Schema
  import Ecto.Changeset

  alias ChessEnabled.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  schema "queue_ccs" do
    field :type, :string
    field :next_idx, :integer

    timestamps()
  end
end
