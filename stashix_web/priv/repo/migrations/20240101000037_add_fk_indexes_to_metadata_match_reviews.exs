defmodule Stashix.Repo.Migrations.AddFkIndexesToMetadataMatchReviews do
  use Ecto.Migration

  def change do
    create index(:metadata_match_reviews, [:book_id])
    create index(:metadata_match_reviews, [:series_id])
  end
end
