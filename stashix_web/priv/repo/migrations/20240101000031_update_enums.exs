defmodule Stashix.Repo.Migrations.UpdateEnums do
  use Ecto.Migration

  # Adds MetronInfo-spec creator roles and information sources missing from initial enums.
  # "Cover Artist" is kept as-is; MetronInfo calls this role "Cover".
  def up do
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Script'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Story'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Plot'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Interviewer'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Artist'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Breakdowns'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Illustrator'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Layouts'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Embellisher'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Finishes'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Ink Assists'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Color Separations'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Color Assists'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Color Flats'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Digital Art Technician'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Gray Tone'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Senior Editor'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Managing Editor'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Collection Editor'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Designer'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Logo Design'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Supervising Editor'")
    execute("ALTER TYPE creator_role ADD VALUE IF NOT EXISTS 'Executive Producer'")

    execute("ALTER TYPE information_source ADD VALUE IF NOT EXISTS 'Kitsu'")
    execute("ALTER TYPE information_source ADD VALUE IF NOT EXISTS 'MangaDex'")
    execute("ALTER TYPE information_source ADD VALUE IF NOT EXISTS 'Marvel'")
    execute("ALTER TYPE information_source ADD VALUE IF NOT EXISTS 'MyAnimeList'")
  end

  def down do
    # Postgres does not support removing enum values without recreating the type.
    # A full recreation would need to update all dependent columns — out of scope here.
    :ok
  end
end
