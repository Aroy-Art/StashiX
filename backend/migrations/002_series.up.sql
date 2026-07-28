CREATE TABLE series (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    publisher  TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (library_id, name)
);

CREATE TABLE series_volumes (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    series_id     UUID NOT NULL REFERENCES series(id) ON DELETE CASCADE,
    volume_number INT NOT NULL,
    title         TEXT,
    year          INT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (series_id, volume_number)
);

ALTER TABLE books
    ADD COLUMN series_id UUID REFERENCES series(id) ON DELETE SET NULL,
    ADD COLUMN volume_id UUID REFERENCES series_volumes(id) ON DELETE SET NULL;

CREATE INDEX idx_series_library_id ON series(library_id);
CREATE INDEX idx_series_volumes_series_id ON series_volumes(series_id);
CREATE INDEX idx_books_series_id ON books(series_id);
CREATE INDEX idx_books_volume_id ON books(volume_id);
