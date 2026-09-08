defmodule Stashix.Repo.Migrations.CreateBooks do
  use Ecto.Migration

  def up do
    create table(:books, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :library_id, references(:libraries, type: :uuid, on_delete: :delete_all), null: false
      add :series_id, references(:series, type: :uuid, on_delete: :nilify_all)
      add :path, :string, null: false
      add :title, :string, null: false
      add :format, :book_format, null: false
      add :issue_number, :decimal
      add :volume, :integer
      add :year, :integer
      add :publisher_id, references(:publishers, type: :uuid, on_delete: :nilify_all)
      add :imprint_id, references(:imprints, type: :uuid, on_delete: :nilify_all)
      add :page_count, :integer, default: 0
      add :file_size, :bigint, default: 0
      add :language, :string, default: "en"
      add :summary, :text
      add :age_rating, :age_rating, default: "unknown"
      add :adult, :boolean, default: false
      add :type, :string, default: "issue"
      add :file_hash, :string
      add :last_modified, :naive_datetime
      add :deleted_at, :naive_datetime
      add :collection_title, :string
      add :alternative_number, :string
      add :isbn, :string
      add :upc, :string
      add :community_rating, :float

      timestamps()
    end

    create unique_index(:books, [:path])
    create index(:books, [:library_id])
    create index(:books, [:series_id])
    create index(:books, [:format])
    create index(:books, [:deleted_at])

    execute("ALTER TABLE books ADD COLUMN search_vec tsvector")
    execute("CREATE INDEX books_search_vec_gin ON books USING GIN(search_vec)")

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

    execute("""
    CREATE TRIGGER books_search_vec_trigger
    BEFORE INSERT OR UPDATE ON books
    FOR EACH ROW EXECUTE FUNCTION books_search_vec_update();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS books_search_vec_trigger ON books")
    execute("DROP FUNCTION IF EXISTS books_search_vec_update()")
    drop table(:books)
  end
end
