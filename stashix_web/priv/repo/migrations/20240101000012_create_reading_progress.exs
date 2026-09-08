defmodule Stashix.Repo.Migrations.CreateReadingProgress do
  use Ecto.Migration

  def change do
    create table(:reading_progress, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :current_page, :integer, default: 0, null: false

      add :updated_at, :naive_datetime, null: false
    end

    create unique_index(:reading_progress, [:user_id, :book_id])
  end
end
