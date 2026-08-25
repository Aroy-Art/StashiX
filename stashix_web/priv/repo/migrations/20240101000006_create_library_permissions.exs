defmodule Stashix.Repo.Migrations.CreateLibraryPermissions do
  use Ecto.Migration

  def change do
    create table(:library_permissions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :library_id, references(:libraries, type: :uuid, on_delete: :delete_all), null: false
      add :can_read, :boolean, default: true, null: false
      add :max_age_rating, :age_rating, default: "everyone"

      timestamps()
    end

    create unique_index(:library_permissions, [:user_id, :library_id])
  end
end
