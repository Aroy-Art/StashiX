defmodule Stashix.Repo.Migrations.AddYearsToSeries do
  use Ecto.Migration

  def change do
    alter table(:series) do
      add :start_year, :integer
      add :end_year, :integer
    end
  end
end
