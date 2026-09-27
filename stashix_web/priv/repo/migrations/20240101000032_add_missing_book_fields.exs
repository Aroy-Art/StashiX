defmodule Stashix.Repo.Migrations.AddMissingBookFields do
  use Ecto.Migration

  def change do
    alter table(:books) do
      add :cover_date, :date
      add :store_date, :date
      add :notes, :text
      add :community_rating_count, :integer
    end

    alter table(:book_story_arcs) do
      add :arc_number, :integer
      add :external_id, :string
    end
  end
end
