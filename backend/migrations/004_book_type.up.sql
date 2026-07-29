CREATE TYPE book_type AS ENUM ('issue', 'standalone');

ALTER TABLE books
    DROP COLUMN IF EXISTS series_id,
    DROP COLUMN IF EXISTS volume_id,
    ADD COLUMN type book_type NOT NULL DEFAULT 'issue';

DROP INDEX IF EXISTS idx_books_series_id;
DROP INDEX IF EXISTS idx_books_volume_id;

CREATE INDEX idx_books_type ON books(type);
