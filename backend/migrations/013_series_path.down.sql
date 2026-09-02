ALTER TABLE series DROP CONSTRAINT series_library_id_path_key;
ALTER TABLE series ADD CONSTRAINT series_library_id_name_key UNIQUE (library_id, name);
ALTER TABLE series DROP COLUMN path;
