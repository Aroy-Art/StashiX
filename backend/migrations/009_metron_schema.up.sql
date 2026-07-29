-- Extend age_rating enum
ALTER TYPE age_rating ADD VALUE IF NOT EXISTS 'teen_plus';
ALTER TYPE age_rating ADD VALUE IF NOT EXISTS 'adult';

-- New enums
CREATE TYPE comic_format AS ENUM (
    'Annual',
    'Digital Chapter',
    'Graphic Novel',
    'Hardcover',
    'Limited Series',
    'Omnibus',
    'One-Shot',
    'Single Issue',
    'Trade Paperback'
);

CREATE TYPE information_source AS ENUM (
    'AniList',
    'Comic Vine',
    'Grand Comics Database',
    'Kitsu',
    'MangaDex',
    'MangaUpdates',
    'Marvel',
    'Metron',
    'MyAnimeList',
    'League of Comic Geeks'
);

CREATE TYPE creator_role AS ENUM (
    'Writer',
    'Script',
    'Story',
    'Plot',
    'Interviewer',
    'Artist',
    'Penciller',
    'Breakdowns',
    'Illustrator',
    'Layouts',
    'Inker',
    'Embellisher',
    'Finishes',
    'Ink Assists',
    'Colorist',
    'Color Separations',
    'Color Assists',
    'Color Flats',
    'Digital Art Technician',
    'Gray Tone',
    'Letterer',
    'Cover',
    'Editor',
    'Consulting Editor',
    'Assistant Editor',
    'Associate Editor',
    'Group Editor',
    'Senior Editor',
    'Managing Editor',
    'Collection Editor',
    'Production',
    'Designer',
    'Logo Design',
    'Translator',
    'Supervising Editor',
    'Executive Editor',
    'Editor In Chief',
    'President',
    'Publisher',
    'Chief Creative Officer',
    'Executive Producer',
    'Other'
);

-- Publishers (normalized, replaces free-text publisher column)
CREATE TABLE publishers (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name       TEXT NOT NULL UNIQUE,
    source     information_source,
    source_id  TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Imprints (child of publisher)
CREATE TABLE imprints (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    publisher_id UUID NOT NULL REFERENCES publishers(id) ON DELETE CASCADE,
    name         TEXT NOT NULL,
    source_id    TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (publisher_id, name)
);

-- Series updates
ALTER TABLE series
    ADD COLUMN sort_name    TEXT,
    ADD COLUMN volume       INT,
    ADD COLUMN language     CHAR(2) NOT NULL DEFAULT 'en',
    ADD COLUMN format       comic_format,
    ADD COLUMN issue_count  INT,
    ADD COLUMN volume_count INT,
    ADD COLUMN publisher_id UUID REFERENCES publishers(id) ON DELETE SET NULL,
    ADD COLUMN imprint_id   UUID REFERENCES imprints(id) ON DELETE SET NULL;

CREATE TABLE series_alternative_names (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    series_id UUID NOT NULL REFERENCES series(id) ON DELETE CASCADE,
    name      TEXT NOT NULL,
    language  CHAR(2) NOT NULL DEFAULT 'en',
    source_id TEXT
);

CREATE TABLE series_external_ids (
    series_id  UUID NOT NULL REFERENCES series(id) ON DELETE CASCADE,
    source     information_source NOT NULL,
    source_id  TEXT NOT NULL,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (series_id, source)
);

CREATE INDEX idx_series_alternative_names_series_id ON series_alternative_names(series_id);

-- Book updates
ALTER TABLE books
    ADD COLUMN collection_title        TEXT,
    ADD COLUMN alternative_number      TEXT,
    ADD COLUMN manga_volume            TEXT,
    ADD COLUMN cover_date              DATE,
    ADD COLUMN store_date              DATE,
    ADD COLUMN notes                   TEXT,
    ADD COLUMN isbn                    TEXT,
    ADD COLUMN upc                     TEXT,
    ADD COLUMN community_rating        DECIMAL(3,1) CHECK (community_rating >= 0 AND community_rating <= 5),
    ADD COLUMN community_rating_count  INT,
    ADD COLUMN comic_format            comic_format,
    ADD COLUMN last_modified           TIMESTAMPTZ,
    ADD COLUMN publisher_id            UUID REFERENCES publishers(id) ON DELETE SET NULL,
    ADD COLUMN imprint_id              UUID REFERENCES imprints(id) ON DELETE SET NULL;

CREATE TABLE book_external_ids (
    book_id    UUID NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    source     information_source NOT NULL,
    source_id  TEXT NOT NULL,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (book_id, source)
);

CREATE TABLE book_urls (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id    UUID NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    url        TEXT NOT NULL,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_book_urls_book_id ON book_urls(book_id);

-- Genres (normalized)
CREATE TABLE genres (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name      TEXT NOT NULL UNIQUE,
    source_id TEXT
);

CREATE TABLE book_genres (
    book_id  UUID NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    genre_id UUID NOT NULL REFERENCES genres(id) ON DELETE CASCADE,
    PRIMARY KEY (book_id, genre_id)
);

-- Tags (normalized)
CREATE TABLE tags (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name      TEXT NOT NULL UNIQUE,
    source_id TEXT
);

CREATE TABLE book_tags (
    book_id UUID NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    tag_id  UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (book_id, tag_id)
);

-- Story arcs
CREATE TABLE story_arcs (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name      TEXT NOT NULL UNIQUE,
    source_id TEXT
);

CREATE TABLE book_story_arcs (
    book_id    UUID NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    arc_id     UUID NOT NULL REFERENCES story_arcs(id) ON DELETE CASCADE,
    arc_number INT,
    PRIMARY KEY (book_id, arc_id)
);

-- Characters
CREATE TABLE characters (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name      TEXT NOT NULL UNIQUE,
    source_id TEXT
);

CREATE TABLE book_characters (
    book_id      UUID NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    PRIMARY KEY (book_id, character_id)
);

-- Teams
CREATE TABLE teams (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name      TEXT NOT NULL UNIQUE,
    source_id TEXT
);

CREATE TABLE book_teams (
    book_id UUID NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    PRIMARY KEY (book_id, team_id)
);

-- Universes
CREATE TABLE universes (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL UNIQUE,
    designation TEXT,
    source_id   TEXT
);

CREATE TABLE book_universes (
    book_id     UUID NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    universe_id UUID NOT NULL REFERENCES universes(id) ON DELETE CASCADE,
    PRIMARY KEY (book_id, universe_id)
);

-- Locations
CREATE TABLE locations (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name      TEXT NOT NULL UNIQUE,
    source_id TEXT
);

CREATE TABLE book_locations (
    book_id     UUID NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    location_id UUID NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
    PRIMARY KEY (book_id, location_id)
);

-- Creators and credits
CREATE TABLE creators (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name      TEXT NOT NULL UNIQUE,
    source_id TEXT
);

CREATE TABLE book_credits (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id    UUID NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    creator_id UUID NOT NULL REFERENCES creators(id) ON DELETE CASCADE,
    role       creator_role NOT NULL
);

CREATE INDEX idx_book_credits_book_id ON book_credits(book_id);

-- Story titles within an issue
CREATE TABLE book_stories (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id    UUID NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    title      TEXT NOT NULL,
    source_id  TEXT,
    sort_order INT NOT NULL DEFAULT 0
);

CREATE INDEX idx_book_stories_book_id ON book_stories(book_id);

-- Prices
CREATE TABLE book_prices (
    id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id UUID NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    country CHAR(2) NOT NULL,
    price   DECIMAL(10,2) NOT NULL
);

CREATE INDEX idx_book_prices_book_id ON book_prices(book_id);

-- Reprints
CREATE TABLE book_reprints (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id   UUID NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    name      TEXT NOT NULL,
    source_id TEXT
);

CREATE INDEX idx_book_reprints_book_id ON book_reprints(book_id);
