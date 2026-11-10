# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.CreateSchema do
  @moduledoc """
  The full schema as of the 0.0.1 release, folded from the development
  migrations. Column order matches the databases those migrations built, so
  `pg_dump --schema-only` of either is identical.
  """
  use Ecto.Migration

  @enums [
    age_rating: ~w(unknown everyone teen teen_plus mature adult explicit),
    book_format: ~w(cbz cbr cb7 epub pdf),
    comic_format: [
      "Single Issue",
      "Trade Paperback",
      "Hardcover",
      "Graphic Novel",
      "Annual",
      "Digital Chapter",
      "Omnibus",
      "Compendium",
      "Treasury",
      "Facsimile Edition",
      "Preview"
    ],
    creator_role: [
      "Writer",
      "Penciller",
      "Inker",
      "Colorist",
      "Letterer",
      "Cover Artist",
      "Editor",
      "Translator",
      "Consulting Editor",
      "Assistant Editor",
      "Associate Editor",
      "Group Editor",
      "Executive Editor",
      "Editor in Chief",
      "Chief Creative Officer",
      "President",
      "Publisher",
      "General Manager",
      "Production",
      "Production Manager",
      "Brand Manager",
      "VP of Business Affairs",
      "VP of Marketing",
      "VP of Publicity",
      "VP of Sales",
      "Other",
      "Script",
      "Story",
      "Plot",
      "Interviewer",
      "Artist",
      "Breakdowns",
      "Illustrator",
      "Layouts",
      "Embellisher",
      "Finishes",
      "Ink Assists",
      "Color Separations",
      "Color Assists",
      "Color Flats",
      "Digital Art Technician",
      "Gray Tone",
      "Senior Editor",
      "Managing Editor",
      "Collection Editor",
      "Designer",
      "Logo Design",
      "Supervising Editor",
      "Executive Producer"
    ],
    information_source: [
      "Metron",
      "Comic Vine",
      "MangaUpdates",
      "AniList",
      "League of Comic Geeks",
      "Grand Comics Database",
      "Unknown",
      "Kitsu",
      "MangaDex",
      "Marvel",
      "MyAnimeList"
    ],
    user_role: ~w(admin user)
  ]

  # Book child tables holding a named item plus an optional source ID.
  @named_book_tables ~w(book_characters book_locations book_reprints book_stories book_teams)a

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS pg_stat_statements"

    for {name, values} <- @enums do
      execute "CREATE TYPE #{name} AS ENUM (#{Enum.map_join(values, ", ", &"'#{&1}'")})"
    end

    # --- Accounts -----------------------------------------------------------

    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :email, :string, null: false
      add :username, :string, null: false
      add :password_hash, :string
      add :role, :user_role, null: false, default: "user"
      add :birth_date, :date
      timestamps()
      add :reader_settings, :map, default: %{}
      add :display_name, :string
      add :token_version, :integer, null: false, default: 0
      add :ui_settings, :map, null: false, default: %{}
      add :last_seen_at, :naive_datetime
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:username])

    create table(:user_sessions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :user_agent, :text
      add :token_version, :integer, null: false
      add :last_seen_at, :naive_datetime, null: false
      add :expires_at, :naive_datetime, null: false
      timestamps(updated_at: false)
      add :ip_address, :string
    end

    create index(:user_sessions, [:user_id])

    # --- Libraries ----------------------------------------------------------

    create table(:libraries, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :root_path, :string, null: false
      add :standalone_folders, :map, default: fragment("'[]'::jsonb")
      timestamps()
    end

    create unique_index(:libraries, [:root_path])

    create table(:library_permissions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :library_id, references(:libraries, type: :uuid, on_delete: :delete_all), null: false
      add :can_read, :boolean, null: false, default: true
      add :max_age_rating, :age_rating, default: "everyone"
      timestamps()
      add :hide_unrated, :boolean, null: false, default: false
    end

    create index(:library_permissions, [:library_id])
    create unique_index(:library_permissions, [:user_id, :library_id])

    # --- Publishers and creators --------------------------------------------

    create table(:publishers, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :source, :information_source
      add :source_id, :string
      timestamps()

      add :canonical_publisher_id,
          references(:publishers, type: :uuid, on_delete: :nilify_all)

      add :hidden, :boolean, null: false, default: false
    end

    create unique_index(:publishers, [:name])
    create index(:publishers, [:canonical_publisher_id])
    create index(:publishers, [:hidden])

    create table(:imprints, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :publisher_id, references(:publishers, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :source_id, :string
      timestamps()
    end

    create unique_index(:imprints, [:publisher_id, :name])

    create table(:creators, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      timestamps()
    end

    create unique_index(:creators, [:name])

    # --- Series -------------------------------------------------------------

    create table(:series, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :library_id, references(:libraries, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :sort_name, :string
      add :volume, :integer
      add :language, :string, default: "en"
      add :format, :comic_format
      add :issue_count, :integer, default: 0
      add :volume_count, :integer, default: 0
      add :ongoing, :boolean, default: false
      add :adult, :boolean, default: false
      add :path, :text
      timestamps()
      add :start_year, :integer
      add :end_year, :integer
      add :deleted_at, :naive_datetime
      add :summary, :text
      add :metadata_locked, :boolean, null: false, default: false
      add :metadata_matched_at, :naive_datetime
      add :metadata_source, :string
      add :status, :string
      add :locked_fields, {:array, :string}, null: false, default: fragment("ARRAY[]::varchar[]")
    end

    create index(:series, [:library_id])
    create index(:series, [:deleted_at])

    create unique_index(:series, [:library_id, :path], name: :series_library_id_path_unique_index)

    create table(:series_alternative_names, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :series_id, references(:series, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :lang, :string, default: "en"
      add :external_id, :string
      timestamps()
    end

    create index(:series_alternative_names, [:series_id])
    create unique_index(:series_alternative_names, [:series_id, :name])

    create table(:series_external_ids, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :series_id, references(:series, type: :uuid, on_delete: :delete_all), null: false
      add :source, :information_source, null: false
      add :source_id, :string, null: false
      add :is_primary, :boolean, default: false
      timestamps()
    end

    create unique_index(:series_external_ids, [:series_id, :source])

    create table(:series_publishers, primary_key: false) do
      add :series_id, references(:series, type: :uuid, on_delete: :delete_all), null: false
      add :publisher_id, references(:publishers, type: :uuid, on_delete: :delete_all), null: false
    end

    create index(:series_publishers, [:series_id])
    create index(:series_publishers, [:publisher_id])
    create unique_index(:series_publishers, [:series_id, :publisher_id])

    # --- Books --------------------------------------------------------------

    create table(:books, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :library_id, references(:libraries, type: :uuid, on_delete: :delete_all), null: false
      add :series_id, references(:series, type: :uuid, on_delete: :nilify_all)
      add :title, :text, null: false
      add :issue_number, :decimal
      add :volume, :integer
      add :year, :integer
      add :imprint_id, references(:imprints, type: :uuid, on_delete: :nilify_all)
      add :page_count, :integer, default: 0
      add :language, :string, default: "en"
      add :summary, :text
      add :age_rating, :age_rating, default: "unknown"
      add :adult, :boolean, default: false
      add :type, :string, default: "issue"
      add :deleted_at, :naive_datetime
      add :collection_title, :string
      add :alternative_number, :string
      add :isbn, :string
      add :upc, :string
      add :community_rating, :float
      timestamps()
      add :search_vec, :tsvector
      add :cover_date, :date
      add :store_date, :date
      add :notes, :text
      add :community_rating_count, :integer
      add :metadata_locked, :boolean, null: false, default: false
      add :metadata_matched_at, :naive_datetime
      add :metadata_source, :string
      add :manga_volume, :string
      add :alternate_series, :string
      add :alternate_count, :integer
      add :series_group, :string
      add :main_character_or_team, :string
      add :scan_information, :text
      add :review, :text
      add :black_and_white, :boolean
      add :manga, :string
      add :locked_fields, {:array, :string}, null: false, default: fragment("ARRAY[]::varchar[]")
    end

    create index(:books, [:library_id])
    create index(:books, [:series_id])
    create index(:books, [:imprint_id])
    create index(:books, [:deleted_at])
    create index(:books, [:search_vec], using: :gin, name: :books_search_vec_gin)

    create table(:book_files, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :path, :text, null: false
      add :format, :varchar, null: false
      add :file_size, :bigint, null: false, default: 0
      add :file_hash, :text
      add :last_modified, :naive_datetime_usec
      add :page_count, :integer, null: false, default: 0
      add :source_format, :text
      add :deleted_at, :naive_datetime_usec
      timestamps(type: :naive_datetime_usec)
    end

    execute "ALTER TABLE book_files ADD CONSTRAINT book_files_path_key UNIQUE (path)"
    create index(:book_files, [:book_id], name: :book_files_book_id_idx)
    create index(:book_files, [:book_id, :format], name: :book_files_format_idx)
    create index(:book_files, [:deleted_at], name: :book_files_deleted_at_idx)

    create table(:book_covers, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :path, :string, null: false
      timestamps()
      add :blurhash, :string
    end

    create unique_index(:book_covers, [:book_id])

    create table(:book_publishers, primary_key: false) do
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :publisher_id, references(:publishers, type: :uuid, on_delete: :delete_all), null: false
    end

    create index(:book_publishers, [:book_id])
    create index(:book_publishers, [:publisher_id])
    create unique_index(:book_publishers, [:book_id, :publisher_id])

    create table(:book_credits, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :creator_id, references(:creators, type: :uuid, on_delete: :delete_all), null: false
      add :role, :creator_role, null: false
      timestamps()
    end

    create index(:book_credits, [:creator_id])
    create unique_index(:book_credits, [:book_id, :creator_id, :role])

    create table(:book_external_ids, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :source, :information_source, null: false
      add :source_id, :string, null: false
      add :is_primary, :boolean, default: false
      timestamps()
    end

    create unique_index(:book_external_ids, [:book_id, :source])

    create table(:book_urls, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :url, :text, null: false
      add :is_primary, :boolean, default: false
      timestamps()
    end

    create index(:book_urls, [:book_id])

    create table(:book_prices, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :amount, :decimal, null: false
      add :country, :string, size: 2, null: false
      timestamps()
    end

    create index(:book_prices, [:book_id])
    create unique_index(:book_prices, [:book_id, :country])

    for table <- ~w(book_genres book_tags)a do
      create table(table, primary_key: false) do
        add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
        add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
        add :name, :string, null: false
        timestamps()
      end

      create unique_index(table, [:book_id, :name])
    end

    for table <- @named_book_tables do
      create table(table, primary_key: false) do
        add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
        add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
        add :name, :string, null: false
        add :external_id, :string
        timestamps()
      end

      create index(table, [:book_id])
      create unique_index(table, [:book_id, :name])
    end

    create table(:book_story_arcs, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      timestamps()
      add :arc_number, :integer
      add :external_id, :string
    end

    create unique_index(:book_story_arcs, [:book_id, :name])

    create table(:book_universes, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :designation, :string
      add :external_id, :string
      timestamps()
    end

    create index(:book_universes, [:book_id])
    create unique_index(:book_universes, [:book_id, :name])

    create table(:reading_progress, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :current_page, :integer, null: false, default: 0
      timestamps(inserted_at: false)
    end

    create index(:reading_progress, [:book_id])
    create unique_index(:reading_progress, [:user_id, :book_id])

    # Full-text search: title, series, publishers and summary, weighted A–D.
    execute """
    CREATE FUNCTION books_search_vec_update() RETURNS trigger
        LANGUAGE plpgsql
        AS $$
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
    $$
    """

    execute """
    CREATE TRIGGER books_search_vec_trigger
      BEFORE INSERT OR UPDATE ON books
      FOR EACH ROW EXECUTE FUNCTION books_search_vec_update()
    """

    # --- Health checks ------------------------------------------------------

    create table(:health_check_results, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :library_id, references(:libraries, type: :uuid, on_delete: :delete_all), null: false
      add :book_file_id, references(:book_files, type: :uuid, on_delete: :delete_all)
      add :check_type, :string, null: false
      add :file_path, :string, null: false
      add :status, :string, null: false
      add :error_message, :text
      add :checked_at, :naive_datetime, null: false
      timestamps()
    end

    create index(:health_check_results, [:book_file_id])
    create index(:health_check_results, [:library_id, :check_type])
    create unique_index(:health_check_results, [:book_file_id, :check_type])
    create unique_index(:health_check_results, [:library_id, :file_path, :check_type])

    # --- Metadata sources ---------------------------------------------------

    create table(:app_settings, primary_key: false) do
      add :key, :string, primary_key: true
      add :value, :map, null: false, default: %{}
      timestamps()
    end

    create table(:metadata_sources, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :source_key, :string, null: false
      add :enabled, :boolean, null: false, default: false
      add :priority, :integer, null: false, default: 100
      add :auto_apply, :boolean, null: false, default: true
      add :config, :binary
      add :rate_limit_per_minute, :integer
      add :last_tested_at, :naive_datetime
      add :last_test_status, :string
      add :last_test_message, :text
      timestamps()
      add :request_interval_ms, :integer
      add :endpoint_limit_per_hour, :integer
    end

    create unique_index(:metadata_sources, [:source_key])

    create table(:metadata_cache, primary_key: false) do
      add :key, :string, primary_key: true
      add :source_key, :string, null: false
      add :url, :text, null: false
      add :body, :map, null: false
      add :expires_at, :naive_datetime, null: false
      timestamps()
    end

    create index(:metadata_cache, [:source_key])
    create index(:metadata_cache, [:expires_at])

    create table(:metadata_match_reviews, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all)
      add :series_id, references(:series, type: :uuid, on_delete: :delete_all)
      add :library_id, references(:libraries, type: :uuid, on_delete: :delete_all)
      add :status, :string, null: false, default: "pending"
      add :query, :map, null: false, default: %{}
      add :candidates, {:array, :map}, null: false, default: fragment("ARRAY[]::jsonb[]")
      add :error, :text
      timestamps()
    end

    create index(:metadata_match_reviews, [:book_id])
    create index(:metadata_match_reviews, [:series_id])
    create index(:metadata_match_reviews, [:library_id])
    create index(:metadata_match_reviews, [:status])

    # One pending review per book, and per series for series-level reviews.
    create unique_index(:metadata_match_reviews, [:book_id],
             name: :metadata_match_reviews_pending_book_index,
             where: "status = 'pending' AND book_id IS NOT NULL"
           )

    create unique_index(:metadata_match_reviews, [:series_id],
             name: :metadata_match_reviews_pending_series_index,
             where: "status = 'pending' AND book_id IS NULL AND series_id IS NOT NULL"
           )

    # --- Background jobs ----------------------------------------------------

    Oban.Migration.up(version: 14)
  end

  def down do
    Oban.Migration.down(version: 1)

    for table <-
          ~w(metadata_match_reviews metadata_cache metadata_sources app_settings
             health_check_results reading_progress book_universes book_story_arcs)a ++
            @named_book_tables ++
            ~w(book_tags book_genres book_prices book_urls book_external_ids book_credits
               book_publishers book_covers book_files books series_publishers
               series_external_ids series_alternative_names series creators imprints
               publishers library_permissions libraries user_sessions users)a do
      drop table(table)
    end

    execute "DROP FUNCTION books_search_vec_update()"

    for {name, _values} <- Enum.reverse(@enums), do: execute("DROP TYPE #{name}")

    execute "DROP EXTENSION IF EXISTS pg_stat_statements"
  end
end
