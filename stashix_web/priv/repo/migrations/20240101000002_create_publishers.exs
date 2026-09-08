defmodule Stashix.Repo.Migrations.CreatePublishers do
  use Ecto.Migration

  def change do
    create table(:publishers, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :source, :information_source
      add :source_id, :string

      timestamps()
    end

    create unique_index(:publishers, [:name])
  end
end
