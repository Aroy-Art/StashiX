defmodule Stashix.Repo.Migrations.FixHealthCheckIntegrityIndex do
  use Ecto.Migration

  def change do
    # Ecto cannot resolve a partial unique index as a conflict_target, so
    # IntegrityFileWorker upserts were silently failing. Replace with a plain
    # unique index — Postgres allows multiple NULLs in non-partial unique
    # indexes, so unsupported-file rows (book_file_id = NULL) are unaffected.
    drop_if_exists unique_index(:health_check_results, [:book_file_id, :check_type],
                     where: "book_file_id IS NOT NULL"
                   )

    create_if_not_exists unique_index(:health_check_results, [:book_file_id, :check_type])
  end
end
