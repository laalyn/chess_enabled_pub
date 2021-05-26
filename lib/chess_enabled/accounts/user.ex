defmodule ChessEnabled.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  schema "users" do
    field :email, :string
    field :password, :string, virtual: true
    field :password_hash, :string
    field :next_idx, :integer

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password, :next_idx], message: "invalid input")
    |> validate_required([:email, :password, :next_idx], message: "some fields are missing")
    |> validate_format(:email, ~r/@/, message: "email is not valid")
    |> validate_length(:password, min: 6, message: "password must be at least 6 characters long")
    |> unique_constraint(:email, message: "email already exists")
    |> change(Argon2.add_hash(attrs["password"]))
  end
end