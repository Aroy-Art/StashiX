defmodule Stashix.Repo.Migrations.AddSummaryToSeries do
  use Ecto.Migration

  def change do
    alter table(:series) do
      add :summary, :text
    end
  end
end
