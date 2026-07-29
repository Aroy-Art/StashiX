DROP TABLE IF EXISTS book_reprints;
DROP TABLE IF EXISTS book_prices;
DROP TABLE IF EXISTS book_stories;
DROP TABLE IF EXISTS book_credits;
DROP TABLE IF EXISTS creators;
DROP TABLE IF EXISTS book_locations;
DROP TABLE IF EXISTS locations;
DROP TABLE IF EXISTS book_universes;
DROP TABLE IF EXISTS universes;
DROP TABLE IF EXISTS book_teams;
DROP TABLE IF EXISTS teams;
DROP TABLE IF EXISTS book_characters;
DROP TABLE IF EXISTS characters;
DROP TABLE IF EXISTS book_story_arcs;
DROP TABLE IF EXISTS story_arcs;
DROP TABLE IF EXISTS book_tags;
DROP TABLE IF EXISTS tags;
DROP TABLE IF EXISTS book_genres;
DROP TABLE IF EXISTS genres;
DROP TABLE IF EXISTS book_urls;
DROP TABLE IF EXISTS book_external_ids;
DROP TABLE IF EXISTS series_external_ids;
DROP TABLE IF EXISTS series_alternative_names;

ALTER TABLE books
    DROP COLUMN IF EXISTS publisher_id,
    DROP COLUMN IF EXISTS imprint_id,
    DROP COLUMN IF EXISTS last_modified,
    DROP COLUMN IF EXISTS comic_format,
    DROP COLUMN IF EXISTS community_rating_count,
    DROP COLUMN IF EXISTS community_rating,
    DROP COLUMN IF EXISTS upc,
    DROP COLUMN IF EXISTS isbn,
    DROP COLUMN IF EXISTS notes,
    DROP COLUMN IF EXISTS store_date,
    DROP COLUMN IF EXISTS cover_date,
    DROP COLUMN IF EXISTS manga_volume,
    DROP COLUMN IF EXISTS alternative_number,
    DROP COLUMN IF EXISTS collection_title;

ALTER TABLE series
    DROP COLUMN IF EXISTS imprint_id,
    DROP COLUMN IF EXISTS publisher_id,
    DROP COLUMN IF EXISTS volume_count,
    DROP COLUMN IF EXISTS issue_count,
    DROP COLUMN IF EXISTS format,
    DROP COLUMN IF EXISTS language,
    DROP COLUMN IF EXISTS volume,
    DROP COLUMN IF EXISTS sort_name;

DROP TABLE IF EXISTS imprints;
DROP TABLE IF EXISTS publishers;

DROP TYPE IF EXISTS creator_role;
DROP TYPE IF EXISTS information_source;
DROP TYPE IF EXISTS comic_format;
