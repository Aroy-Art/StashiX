defmodule Stashix.Repo.Migrations.AddPublisherJoinTables do
  use Ecto.Migration

  def change do
    create table(:book_publishers, primary_key: false) do
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :publisher_id, references(:publishers, type: :uuid, on_delete: :delete_all), null: false
    end

    create index(:book_publishers, [:book_id])
    create index(:book_publishers, [:publisher_id])
    create unique_index(:book_publishers, [:book_id, :publisher_id])

    create table(:series_publishers, primary_key: false) do
      add :series_id, references(:series, type: :uuid, on_delete: :delete_all), null: false
      add :publisher_id, references(:publishers, type: :uuid, on_delete: :delete_all), null: false
    end

    create index(:series_publishers, [:series_id])
    create index(:series_publishers, [:publisher_id])
    create unique_index(:series_publishers, [:series_id, :publisher_id])

    alter table(:books) do
      remove :publisher_id
    end

    alter table(:series) do
      remove :publisher_id
    end
  end
end
