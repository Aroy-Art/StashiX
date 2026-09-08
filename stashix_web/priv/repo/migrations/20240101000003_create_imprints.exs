defmodule Stashix.Repo.Migrations.CreateImprints do
  use Ecto.Migration

  def change do
    create table(:imprints, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :publisher_id, references(:publishers, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :source_id, :string

      timestamps()
    end

    create unique_index(:imprints, [:publisher_id, :name])
  end
end
