defmodule Stashix.Repo.Migrations.CreateSeriesExternalIds do
  use Ecto.Migration

  def change do
    create table(:series_external_ids, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :series_id, references(:series, type: :uuid, on_delete: :delete_all), null: false
      add :source, :information_source, null: false
      add :source_id, :string, null: false
      add :is_primary, :boolean, default: false

      timestamps()
    end

    create unique_index(:series_external_ids, [:series_id, :source])
  end
end
