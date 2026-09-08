defmodule Stashix.Repo.Migrations.FixBooksSearchVecTrigger do
  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION books_search_vec_update() RETURNS trigger AS $$
    DECLARE
      series_name text;
      publisher_names text;
    BEGIN
      SELECT s.name INTO series_name FROM series s WHERE s.id = NEW.series_id;
      SELECT string_agg(p.name, ' ') INTO publisher_names
        FROM book_publishers bp
        JOIN publishers p ON p.id = bp.publisher_id
        WHERE bp.book_id = NEW.id;
      NEW.search_vec :=
        setweight(to_tsvector('english', coalesce(NEW.title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(series_name, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(publisher_names, '')), 'C') ||
        setweight(to_tsvector('english', coalesce(NEW.summary, '')), 'D');
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)
  end

  def down do
    execute("""
    CREATE OR REPLACE FUNCTION books_search_vec_update() RETURNS trigger AS $$
    DECLARE
      series_name text;
      publisher_name text;
    BEGIN
      SELECT s.name INTO series_name FROM series s WHERE s.id = NEW.series_id;
      SELECT p.name INTO publisher_name FROM publishers p WHERE p.id = NEW.publisher_id;
      NEW.search_vec :=
        setweight(to_tsvector('english', coalesce(NEW.title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(series_name, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(publisher_name, '')), 'C') ||
        setweight(to_tsvector('english', coalesce(NEW.summary, '')), 'D');
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)
  end
end
