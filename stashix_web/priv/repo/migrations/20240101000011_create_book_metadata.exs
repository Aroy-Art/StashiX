defmodule Stashix.Repo.Migrations.CreateBookMetadata do
  use Ecto.Migration

  def change do
    create table(:book_external_ids, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :source, :information_source, null: false
      add :source_id, :string, null: false
      add :is_primary, :boolean, default: false

      timestamps()
    end

    create unique_index(:book_external_ids, [:book_id, :source])

    create table(:book_genres, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false

      timestamps()
    end

    create unique_index(:book_genres, [:book_id, :name])

    create table(:book_tags, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false

      timestamps()
    end

    create unique_index(:book_tags, [:book_id, :name])

    create table(:book_story_arcs, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false

      timestamps()
    end

    create unique_index(:book_story_arcs, [:book_id, :name])

    create table(:book_credits, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :creator_id, references(:creators, type: :uuid, on_delete: :delete_all), null: false
      add :role, :creator_role, null: false

      timestamps()
    end

    create unique_index(:book_credits, [:book_id, :creator_id, :role])
  end
end
