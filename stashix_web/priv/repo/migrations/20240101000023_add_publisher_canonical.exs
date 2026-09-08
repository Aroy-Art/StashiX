defmodule Stashix.Repo.Migrations.AddPublisherCanonical do
  use Ecto.Migration

  def change do
    alter table(:publishers) do
      add :canonical_publisher_id,
          references(:publishers, type: :binary_id, on_delete: :nilify_all), null: true
    end

    create index(:publishers, [:canonical_publisher_id])
  end
end
