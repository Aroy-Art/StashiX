DROP INDEX IF EXISTS idx_books_file_hash;
DROP INDEX IF EXISTS idx_books_deleted_at;
ALTER TABLE books DROP COLUMN IF EXISTS file_hash;
ALTER TABLE books DROP COLUMN IF EXISTS deleted_at;
