ALTER TABLE series ADD COLUMN path TEXT NOT NULL DEFAULT '';

-- Populate path from the directory of each series' associated books
UPDATE series s
SET path = regexp_replace(b.path, '/[^/]*$', '')
FROM (
    SELECT DISTINCT ON (series_id) series_id, path
    FROM books
    WHERE series_id IS NOT NULL
    ORDER BY series_id, path
) b
WHERE s.id = b.series_id;

-- Series with no books get a synthetic placeholder so the unique constraint doesn't fail
UPDATE series SET path = '::orphan::' || name WHERE path = '';

ALTER TABLE series DROP CONSTRAINT series_library_id_name_key;
ALTER TABLE series ADD CONSTRAINT series_library_id_path_key UNIQUE (library_id, path);
