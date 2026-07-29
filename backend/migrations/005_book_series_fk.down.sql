DROP INDEX IF EXISTS idx_books_series_id;

ALTER TABLE books DROP COLUMN IF EXISTS series_id;
