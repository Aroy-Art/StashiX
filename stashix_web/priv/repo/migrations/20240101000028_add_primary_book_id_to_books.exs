defmodule Stashix.Repo.Migrations.AddPrimaryBookIdToBooks do
  use Ecto.Migration

  def change do
    alter table(:books) do
      add :primary_book_id,
          references(:books, type: :binary_id, on_delete: :nilify_all),
          null: true
    end

    create index(:books, [:primary_book_id])
  end
end
