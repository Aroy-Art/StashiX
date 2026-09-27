defmodule Stashix.Repo.Migrations.AddMetadataSources do
  use Ecto.Migration

  def change do
    create table(:metadata_sources, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :source_key, :string, null: false
      add :enabled, :boolean, null: false, default: false
      add :priority, :integer, null: false, default: 100
      add :auto_apply, :boolean, null: false, default: true
      add :config, :binary
      add :rate_limit_per_minute, :integer
      add :last_tested_at, :naive_datetime
      add :last_test_status, :string
      add :last_test_message, :text

      timestamps()
    end

    create unique_index(:metadata_sources, [:source_key])

    create table(:metadata_match_reviews, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all)
      add :series_id, references(:series, type: :uuid, on_delete: :delete_all)
      add :library_id, references(:libraries, type: :uuid, on_delete: :delete_all)
      add :status, :string, null: false, default: "pending"
      add :query, :map, null: false, default: %{}
      add :candidates, {:array, :map}, null: false, default: []
      add :error, :text

      timestamps()
    end

    create index(:metadata_match_reviews, [:status])
    create index(:metadata_match_reviews, [:library_id])

    create unique_index(:metadata_match_reviews, [:book_id],
             where: "status = 'pending' AND book_id IS NOT NULL",
             name: :metadata_match_reviews_pending_book_index
           )

    create unique_index(:metadata_match_reviews, [:series_id],
             where: "status = 'pending' AND book_id IS NULL AND series_id IS NOT NULL",
             name: :metadata_match_reviews_pending_series_index
           )

    create table(:app_settings, primary_key: false) do
      add :key, :string, primary_key: true
      add :value, :map, null: false, default: %{}

      timestamps()
    end

    for table <- [:books, :series] do
      alter table(table) do
        add :metadata_locked, :boolean, null: false, default: false
        add :metadata_matched_at, :naive_datetime
        add :metadata_source, :string
      end
    end
  end
end
