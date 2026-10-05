defmodule Stashix.Repo.Migrations.AddTokenVersionToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :token_version, :integer, null: false, default: 0
    end
  end
end
