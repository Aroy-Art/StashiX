defmodule Stashix.Repo.Migrations.AddMetroninfoTables do
  use Ecto.Migration

  def change do
    create table(:series_alternative_names, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :series_id, references(:series, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :lang, :string, default: "en"
      add :external_id, :string

      timestamps()
    end

    create index(:series_alternative_names, [:series_id])
    create unique_index(:series_alternative_names, [:series_id, :name])

    create table(:book_stories, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :external_id, :string

      timestamps()
    end

    create index(:book_stories, [:book_id])
    create unique_index(:book_stories, [:book_id, :name])

    create table(:book_characters, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :external_id, :string

      timestamps()
    end

    create index(:book_characters, [:book_id])
    create unique_index(:book_characters, [:book_id, :name])

    create table(:book_teams, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :external_id, :string

      timestamps()
    end

    create index(:book_teams, [:book_id])
    create unique_index(:book_teams, [:book_id, :name])

    create table(:book_universes, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :designation, :string
      add :external_id, :string

      timestamps()
    end

    create index(:book_universes, [:book_id])
    create unique_index(:book_universes, [:book_id, :name])

    create table(:book_locations, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :external_id, :string

      timestamps()
    end

    create index(:book_locations, [:book_id])
    create unique_index(:book_locations, [:book_id, :name])

    create table(:book_reprints, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :external_id, :string

      timestamps()
    end

    create index(:book_reprints, [:book_id])
    create unique_index(:book_reprints, [:book_id, :name])

    create table(:book_urls, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :url, :text, null: false
      add :is_primary, :boolean, default: false

      timestamps()
    end

    create index(:book_urls, [:book_id])

    create table(:book_prices, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :amount, :decimal, null: false
      add :country, :string, size: 2, null: false

      timestamps()
    end

    create index(:book_prices, [:book_id])
    create unique_index(:book_prices, [:book_id, :country])
  end
end
