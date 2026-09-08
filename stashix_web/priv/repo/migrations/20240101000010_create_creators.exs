defmodule Stashix.Repo.Migrations.CreateCreators do
  use Ecto.Migration

  def change do
    create table(:creators, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false

      timestamps()
    end

    create unique_index(:creators, [:name])
  end
end
