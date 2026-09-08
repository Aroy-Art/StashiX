defmodule Stashix.Repo.Migrations.CreateEnums do
  use Ecto.Migration

  def up do
    execute("CREATE TYPE user_role AS ENUM ('admin', 'user')")

    execute("CREATE TYPE book_format AS ENUM ('cbz', 'cbr', 'cb7', 'epub', 'pdf')")

    execute(
      "CREATE TYPE age_rating AS ENUM ('unknown', 'everyone', 'teen', 'teen_plus', 'mature', 'adult', 'explicit')"
    )

    execute(
      "CREATE TYPE comic_format AS ENUM ('Single Issue', 'Trade Paperback', 'Hardcover', 'Graphic Novel', 'Annual', 'Digital Chapter', 'Omnibus', 'Compendium', 'Treasury', 'Facsimile Edition', 'Preview')"
    )

    execute(
      "CREATE TYPE information_source AS ENUM ('Metron', 'Comic Vine', 'MangaUpdates', 'AniList', 'League of Comic Geeks', 'Grand Comics Database', 'Unknown')"
    )

    execute(
      "CREATE TYPE creator_role AS ENUM ('Writer', 'Penciller', 'Inker', 'Colorist', 'Letterer', 'Cover Artist', 'Editor', 'Translator', 'Consulting Editor', 'Assistant Editor', 'Associate Editor', 'Group Editor', 'Executive Editor', 'Editor in Chief', 'Chief Creative Officer', 'President', 'Publisher', 'General Manager', 'Production', 'Production Manager', 'Brand Manager', 'VP of Business Affairs', 'VP of Marketing', 'VP of Publicity', 'VP of Sales', 'Other')"
    )
  end

  def down do
    execute("DROP TYPE IF EXISTS creator_role")
    execute("DROP TYPE IF EXISTS information_source")
    execute("DROP TYPE IF EXISTS comic_format")
    execute("DROP TYPE IF EXISTS age_rating")
    execute("DROP TYPE IF EXISTS book_format")
    execute("DROP TYPE IF EXISTS user_role")
  end
end
