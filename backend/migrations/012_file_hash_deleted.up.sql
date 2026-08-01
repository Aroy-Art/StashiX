ALTER TABLE books ADD COLUMN file_hash TEXT;
ALTER TABLE books ADD COLUMN deleted_at TIMESTAMPTZ;

CREATE INDEX idx_books_file_hash ON books(file_hash) WHERE file_hash IS NOT NULL;
CREATE INDEX idx_books_deleted_at ON books(deleted_at) WHERE deleted_at IS NOT NULL;
