defmodule ChessEnabled.Repo.Migrations.CreateMovesIndices do
  use Ecto.Migration

  def change do
    create index(:moves, [:row])
    create index(:moves, [:col])
    create index(:moves, [:idx])
  end
end
