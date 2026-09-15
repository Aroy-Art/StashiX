defmodule Stashix.Repo.Migrations.BackfillBooksSearchVec do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE books b
    SET search_vec =
      setweight(to_tsvector('english', coalesce(b.title, '')), 'A') ||
      setweight(to_tsvector('english', coalesce((SELECT s.name FROM series s WHERE s.id = b.series_id), '')), 'B') ||
      setweight(to_tsvector('english', coalesce((SELECT string_agg(p.name, ' ') FROM book_publishers bp JOIN publishers p ON p.id = bp.publisher_id WHERE bp.book_id = b.id), '')), 'C') ||
      setweight(to_tsvector('english', coalesce(b.summary, '')), 'D')
    WHERE b.search_vec IS NULL
    """)
  end

  def down do
    :ok
  end
end
