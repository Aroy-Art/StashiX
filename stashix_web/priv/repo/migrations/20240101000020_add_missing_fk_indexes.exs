defmodule StashixWeb.Repo.Migrations.AddMissingFkIndexes do
  use Ecto.Migration

  def change do
    create index(:book_credits, [:creator_id])
    create index(:library_permissions, [:library_id])
    create index(:reading_progress, [:book_id])
    create index(:series, [:publisher_id])
    create index(:books, [:publisher_id])
    create index(:books, [:imprint_id])
  end
end
