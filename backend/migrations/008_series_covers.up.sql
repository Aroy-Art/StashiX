CREATE TABLE series_covers (
    series_id  UUID PRIMARY KEY REFERENCES series(id) ON DELETE CASCADE,
    path       TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
