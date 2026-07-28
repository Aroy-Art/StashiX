CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE user_role AS ENUM ('admin', 'user');
CREATE TYPE book_format AS ENUM ('cbz', 'cbr', 'cb7', 'epub', 'pdf');
CREATE TYPE age_rating AS ENUM ('unknown', 'everyone', 'teen', 'mature', 'explicit');

CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email       TEXT NOT NULL UNIQUE,
    username    TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role        user_role NOT NULL DEFAULT 'user',
    birth_date  DATE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE libraries (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    root_path   TEXT NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- null max_age_rating means no restriction
CREATE TABLE library_permissions (
    user_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    library_id     UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    can_read       BOOLEAN NOT NULL DEFAULT TRUE,
    max_age_rating age_rating,
    PRIMARY KEY (user_id, library_id)
);

CREATE TABLE books (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_id   UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    path         TEXT NOT NULL UNIQUE,
    title        TEXT NOT NULL,
    series       TEXT,
    issue_number TEXT,
    volume       INT,
    year         INT,
    publisher    TEXT,
    format       book_format NOT NULL,
    page_count   INT NOT NULL DEFAULT 0,
    file_size    BIGINT NOT NULL DEFAULT 0,
    age_rating   age_rating NOT NULL DEFAULT 'unknown',
    language     TEXT,
    summary      TEXT,
    search_vec   TSVECTOR,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_books_library_id ON books(library_id);
CREATE INDEX idx_books_series ON books(series);
CREATE INDEX idx_books_search ON books USING GIN(search_vec);

CREATE TABLE book_covers (
    book_id    UUID PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
    path       TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE reading_progress (
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    book_id    UUID NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    current_page INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, book_id)
);

-- auto-update search_vec on insert/update
CREATE OR REPLACE FUNCTION books_search_vec_update() RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vec := to_tsvector('english',
        coalesce(NEW.title, '') || ' ' ||
        coalesce(NEW.series, '') || ' ' ||
        coalesce(NEW.publisher, '') || ' ' ||
        coalesce(NEW.summary, '')
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER books_search_vec_trigger
    BEFORE INSERT OR UPDATE ON books
    FOR EACH ROW EXECUTE FUNCTION books_search_vec_update();
