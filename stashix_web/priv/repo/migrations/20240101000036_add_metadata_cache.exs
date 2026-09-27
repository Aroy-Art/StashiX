defmodule Stashix.Repo.Migrations.AddMetadataCache do
  use Ecto.Migration

  def change do
    create table(:metadata_cache, primary_key: false) do
      add :key, :string, primary_key: true
      add :source_key, :string, null: false
      add :url, :text, null: false
      add :body, :map, null: false
      add :expires_at, :naive_datetime, null: false

      timestamps()
    end

    create index(:metadata_cache, [:expires_at])
    create index(:metadata_cache, [:source_key])
  end
end
