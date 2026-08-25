defmodule Stashix.Repo.Migrations.CreateBookCovers do
  use Ecto.Migration

  def change do
    create table(:book_covers, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :path, :string, null: false

      timestamps()
    end

    create unique_index(:book_covers, [:book_id])
  end
end
