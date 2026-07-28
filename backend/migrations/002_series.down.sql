DROP INDEX IF EXISTS idx_books_volume_id;
DROP INDEX IF EXISTS idx_books_series_id;
DROP INDEX IF EXISTS idx_series_volumes_series_id;
DROP INDEX IF EXISTS idx_series_library_id;
ALTER TABLE books DROP COLUMN IF EXISTS volume_id;
ALTER TABLE books DROP COLUMN IF EXISTS series_id;
DROP TABLE IF EXISTS series_volumes;
DROP TABLE IF EXISTS series;
