defmodule ChessEnabled.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string
      add :password_hash, :string
      add :next_idx, :bigint

      timestamps([type: :utc_datetime_usec])
    end

    create unique_index(:users, [:email])
  end
end
