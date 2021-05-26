defmodule ChessEnabled.Repo.Migrations.CreateQueueCCs do
  use Ecto.Migration

  def change do
    # concurrency control
    create table(:queue_ccs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string
      add :next_idx, :integer

      timestamps([type: :utc_datetime_usec])
    end

    execute "insert into queue_ccs values (gen_random_uuid(), 'chess', 0, localtimestamp, localtimestamp)"
  end
end
