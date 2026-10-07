defmodule Stashix.Repo.Migrations.AddLastSeenAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :last_seen_at, :utc_datetime, null: true
    end
  end
end
