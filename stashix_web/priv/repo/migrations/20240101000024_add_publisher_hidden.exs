defmodule Stashix.Repo.Migrations.AddPublisherHidden do
  use Ecto.Migration

  def change do
    alter table(:publishers) do
      add :hidden, :boolean, default: false, null: false
    end

    create index(:publishers, [:hidden])
  end
end
