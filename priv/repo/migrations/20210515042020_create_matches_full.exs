defmodule ChessEnabled.Repo.Migrations.CreateMatchesFull do
  use Ecto.Migration

  def change do
    create table(:matches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string
      add :closed, :boolean
      add :next_idx, :bigint

      timestamps([type: :utc_datetime_usec])
    end

    create table(:players, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :idx, :integer
      add :status, :string
      add :elo_delta, :integer
      add :user_id, references(:users, [type: :binary_id, on_delete: :delete_all])
      add :match_id, references(:matches, [type: :binary_id, on_delete: :delete_all])

      timestamps([type: :utc_datetime_usec])
    end

    create table(:pieces, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string
      add :match_id, references(:matches, [type: :binary_id, on_delete: :delete_all])

      timestamps([type: :utc_datetime_usec])
    end

    create table(:moves, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :idx, :integer
      add :row, :integer
      add :col, :integer
      add :player_id, references(:players, [type: :binary_id, on_delete: :delete_all])
      add :piece_id, references(:pieces, [type: :binary_id, on_delete: :delete_all])

      timestamps([type: :utc_datetime_usec])
    end

    create index(:players, [:user_id])
    create index(:players, [:match_id])
    create index(:pieces, [:match_id])
    create index(:moves, [:player_id])
    create index(:moves, [:piece_id])
  end
end
