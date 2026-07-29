ALTER TABLE books
    ADD COLUMN series_id UUID REFERENCES series(id) ON DELETE SET NULL;

CREATE INDEX idx_books_series_id ON books(series_id);
