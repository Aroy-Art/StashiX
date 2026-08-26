defmodule Stashix.Repo.Migrations.AddDeletedAtToSeries do
  use Ecto.Migration

  def change do
    alter table(:series) do
      add :deleted_at, :naive_datetime
    end

    create index(:series, [:deleted_at])
  end
end
