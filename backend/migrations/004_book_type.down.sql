DROP INDEX IF EXISTS idx_books_type;

ALTER TABLE books
    DROP COLUMN IF EXISTS type,
    ADD COLUMN series_id UUID REFERENCES series(id) ON DELETE SET NULL,
    ADD COLUMN volume_id UUID REFERENCES series_volumes(id) ON DELETE SET NULL;

CREATE INDEX idx_books_series_id ON books(series_id);
CREATE INDEX idx_books_volume_id ON books(volume_id);

DROP TYPE IF EXISTS book_type;
