defmodule Stashix.Repo.Migrations.AddHideUnratedToLibraryPermissions do
  use Ecto.Migration

  def change do
    alter table(:library_permissions) do
      add :hide_unrated, :boolean, null: false, default: false
    end
  end
end
