defmodule ChessEnabled.Repo.Migrations.CreateQueue do
  use Ecto.Migration

  def change do
    create table(:queue, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string
      add :user_id, references(:users, [type: :binary_id, on_delete: :delete_all])

      timestamps([type: :utc_datetime_usec])
    end

    # no unique index for now bc potential to queue for more than one
    create index(:queue, [:user_id])
  end
end
