defmodule Stashix.Repo.Migrations.AddBlurhashToBookCovers do
  use Ecto.Migration

  def change do
    alter table(:book_covers) do
      add :blurhash, :string
    end
  end
end
