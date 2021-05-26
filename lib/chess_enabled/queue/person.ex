defmodule ChessEnabled.Queue.Person do
  use Ecto.Schema
  import Ecto.Changeset

  alias ChessEnabled.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  schema "queue" do
    field :type, :string
    belongs_to :user, User

    timestamps()
  end
end
