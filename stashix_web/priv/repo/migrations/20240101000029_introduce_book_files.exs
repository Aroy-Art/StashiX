defmodule Stashix.Repo.Migrations.IntroduceBookFiles do
  use Ecto.Migration

  def change do
    execute """
    CREATE TABLE book_files (
      id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
      book_id UUID NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      path TEXT NOT NULL,
      format VARCHAR NOT NULL,
      file_size BIGINT NOT NULL DEFAULT 0,
      file_hash TEXT,
      last_modified TIMESTAMP,
      page_count INTEGER NOT NULL DEFAULT 0,
      source_format TEXT,
      deleted_at TIMESTAMP,
      inserted_at TIMESTAMP NOT NULL,
      updated_at TIMESTAMP NOT NULL,
      CONSTRAINT book_files_path_key UNIQUE (path)
    )
    """

    execute """
    INSERT INTO book_files (book_id, path, format, file_size, file_hash, last_modified, page_count, source_format, deleted_at, inserted_at, updated_at)
    SELECT id, path, format, COALESCE(file_size, 0), file_hash, last_modified, COALESCE(page_count, 0), source_format, deleted_at, inserted_at, updated_at
    FROM books
    WHERE primary_book_id IS NULL AND path IS NOT NULL
    """

    execute """
    INSERT INTO book_files (book_id, path, format, file_size, file_hash, last_modified, page_count, source_format, deleted_at, inserted_at, updated_at)
    SELECT primary_book_id, path, format, COALESCE(file_size, 0), file_hash, last_modified, COALESCE(page_count, 0), source_format, deleted_at, inserted_at, updated_at
    FROM books
    WHERE primary_book_id IS NOT NULL AND path IS NOT NULL
    """

    execute """
    DELETE FROM book_covers WHERE book_id IN (SELECT id FROM books WHERE primary_book_id IS NOT NULL)
    """

    execute """
    DELETE FROM book_publishers WHERE book_id IN (SELECT id FROM books WHERE primary_book_id IS NOT NULL)
    """

    execute """
    DELETE FROM books WHERE primary_book_id IS NOT NULL
    """

    execute """
    ALTER TABLE books
      DROP COLUMN IF EXISTS path,
      DROP COLUMN IF EXISTS format,
      DROP COLUMN IF EXISTS file_size,
      DROP COLUMN IF EXISTS file_hash,
      DROP COLUMN IF EXISTS last_modified,
      DROP COLUMN IF EXISTS source_format,
      DROP COLUMN IF EXISTS primary_book_id
    """

    execute "CREATE INDEX book_files_book_id_idx ON book_files(book_id)"
    execute "CREATE INDEX book_files_format_idx ON book_files(book_id, format)"
    execute "CREATE INDEX book_files_deleted_at_idx ON book_files(deleted_at)"
  end
end
