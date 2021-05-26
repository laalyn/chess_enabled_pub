defmodule ChessEnabled.Repo.Migrations.CreateExtensions do
  use Ecto.Migration

  def change do
    execute "create extension pgcrypto"
  end
end
