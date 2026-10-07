defmodule Stashix.Repo.Migrations.AddUniqueSeriesPath do
  use Ecto.Migration

  def up do
    # Delete duplicate series, keeping the one with books. For duplicates where
    # neither or both have books, keep the one with the lower inserted_at.
    execute("""
    DELETE FROM series
    WHERE id IN (
      SELECT id FROM (
        SELECT
          id,
          ROW_NUMBER() OVER (
            PARTITION BY library_id, path
            ORDER BY
              (SELECT COUNT(*) FROM books WHERE books.series_id = series.id) DESC,
              inserted_at ASC
          ) AS rn
        FROM series
        WHERE path IS NOT NULL
      ) ranked
      WHERE rn > 1
    )
    """)

    create unique_index(:series, [:library_id, :path],
             where: "path IS NOT NULL",
             name: :series_library_id_path_unique_index
           )
  end

  def down do
    drop index(:series, [:library_id, :path], name: :series_library_id_path_unique_index)
  end
end
