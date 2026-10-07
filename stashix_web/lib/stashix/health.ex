defmodule Stashix.Health do
  import Ecto.Query

  alias Stashix.Repo
  alias Stashix.Library.{Book, BookCover, BookFile, Series}
  alias Stashix.Health.CheckResult

  # ── DB-backed health queries ──────────────────────────────────────────────

  def list_missing_files(library_id) do
    from(bf in BookFile,
      join: b in Book,
      on: b.id == bf.book_id,
      where: b.library_id == ^library_id and not is_nil(bf.deleted_at),
      select: %{
        book_file_id: bf.id,
        book_id: b.id,
        title: b.title,
        path: bf.path,
        deleted_at: bf.deleted_at
      },
      order_by: [desc: bf.deleted_at]
    )
    |> Repo.all()
  end

  def count_missing_files(library_id) do
    from(bf in BookFile,
      join: b in Book,
      on: b.id == bf.book_id,
      where: b.library_id == ^library_id and not is_nil(bf.deleted_at),
      select: count()
    )
    |> Repo.one()
  end

  def list_zero_page_books(library_id) do
    from(b in Book,
      where:
        b.library_id == ^library_id and
          is_nil(b.deleted_at) and
          (b.page_count == 0 or is_nil(b.page_count)),
      select: %{book_id: b.id, title: b.title, series_id: b.series_id},
      order_by: [asc: b.title]
    )
    |> Repo.all()
  end

  def count_zero_page_books(library_id) do
    from(b in Book,
      where:
        b.library_id == ^library_id and
          is_nil(b.deleted_at) and
          (b.page_count == 0 or is_nil(b.page_count)),
      select: count()
    )
    |> Repo.one()
  end

  def list_books_without_cover(library_id) do
    from(b in Book,
      left_join: c in BookCover,
      on: c.book_id == b.id,
      where: b.library_id == ^library_id and is_nil(b.deleted_at) and is_nil(c.id),
      select: %{book_id: b.id, title: b.title, series_id: b.series_id},
      order_by: [asc: b.title]
    )
    |> Repo.all()
  end

  def count_books_without_cover(library_id) do
    from(b in Book,
      left_join: c in BookCover,
      on: c.book_id == b.id,
      where: b.library_id == ^library_id and is_nil(b.deleted_at) and is_nil(c.id),
      select: count()
    )
    |> Repo.one()
  end

  # Queries series whose path no longer exists on disk. Requires a disk check
  # so we load all series paths and filter in memory.
  def list_orphan_series(library_id) do
    from(s in Series,
      where: s.library_id == ^library_id and is_nil(s.deleted_at) and not is_nil(s.path),
      select: %{series_id: s.id, name: s.name, path: s.path}
    )
    |> Repo.all()
    |> Enum.reject(fn %{path: path} -> File.dir?(path) end)
  end

  def count_orphan_series(library_id) do
    library_id |> list_orphan_series() |> length()
  end

  # ── Integrity / unsupported-file results (persisted by workers) ───────────

  def list_integrity_errors(library_id) do
    from(r in CheckResult,
      join: bf in BookFile,
      on: bf.id == r.book_file_id,
      join: b in Book,
      on: b.id == bf.book_id,
      where:
        r.library_id == ^library_id and
          r.check_type == :integrity and
          r.status == :error,
      select: %{
        result_id: r.id,
        book_file_id: r.book_file_id,
        book_id: b.id,
        title: b.title,
        file_path: r.file_path,
        error_message: r.error_message,
        checked_at: r.checked_at
      },
      order_by: [asc: r.file_path]
    )
    |> Repo.all()
  end

  def count_integrity_errors(library_id) do
    from(r in CheckResult,
      where:
        r.library_id == ^library_id and
          r.check_type == :integrity and
          r.status == :error,
      select: count()
    )
    |> Repo.one()
  end

  def list_unsupported_files(library_id) do
    from(r in CheckResult,
      where: r.library_id == ^library_id and r.check_type == :unsupported_file,
      select: %{result_id: r.id, file_path: r.file_path, checked_at: r.checked_at},
      order_by: [asc: r.file_path]
    )
    |> Repo.all()
  end

  def count_unsupported_files(library_id) do
    from(r in CheckResult,
      where: r.library_id == ^library_id and r.check_type == :unsupported_file,
      select: count()
    )
    |> Repo.one()
  end

  # ── Progress tracking ─────────────────────────────────────────────────────

  def integrity_progress(library_id) do
    total_files =
      from(bf in BookFile,
        join: b in Book,
        on: b.id == bf.book_id,
        where: b.library_id == ^library_id and is_nil(bf.deleted_at),
        select: count()
      )
      |> Repo.one()

    checked =
      from(r in CheckResult,
        where: r.library_id == ^library_id and r.check_type == :integrity,
        select: count()
      )
      |> Repo.one()

    %{total: total_files, checked: checked}
  end

  # ── Upserts ───────────────────────────────────────────────────────────────

  def upsert_integrity_result(library_id, book_file_id, file_path, status, error_message \\ nil) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    attrs = %{
      library_id: library_id,
      book_file_id: book_file_id,
      check_type: :integrity,
      file_path: file_path,
      status: status,
      error_message: error_message,
      checked_at: now
    }

    %CheckResult{}
    |> CheckResult.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:status, :error_message, :checked_at, :updated_at]},
      conflict_target: [:book_file_id, :check_type]
    )
  end

  def upsert_unsupported_file(library_id, file_path) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    attrs = %{
      library_id: library_id,
      check_type: :unsupported_file,
      file_path: file_path,
      status: :error,
      checked_at: now
    }

    %CheckResult{}
    |> CheckResult.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:checked_at, :updated_at]},
      conflict_target: [:library_id, :file_path, :check_type]
    )
  end

  def clear_integrity_results(library_id) do
    from(r in CheckResult,
      where: r.library_id == ^library_id and r.check_type == :integrity
    )
    |> Repo.delete_all()
  end

  def clear_unsupported_file_results(library_id) do
    from(r in CheckResult,
      where: r.library_id == ^library_id and r.check_type == :unsupported_file
    )
    |> Repo.delete_all()
  end

  # ── Summary for all libraries ─────────────────────────────────────────────

  def library_summary(library_id) do
    %{
      missing_files: count_missing_files(library_id),
      zero_page_books: count_zero_page_books(library_id),
      books_without_cover: count_books_without_cover(library_id),
      orphan_series: count_orphan_series(library_id),
      integrity_errors: count_integrity_errors(library_id),
      unsupported_files: count_unsupported_files(library_id)
    }
  end

  # ── Cancellation ─────────────────────────────────────────────────────────

  def cancel_integrity_scan(library_id) do
    Oban.cancel_all_jobs(
      from(j in Oban.Job,
        where:
          j.worker in [
            "Stashix.Health.Workers.IntegrityLibraryWorker",
            "Stashix.Health.Workers.IntegrityFileWorker"
          ] and
            j.state in ["available", "scheduled", "executing", "retryable"] and
            fragment("?->>'library_id'", j.args) == ^library_id
      )
    )

    broadcast(library_id, {:integrity_cancelled, %{library_id: library_id}})
  end

  # ── PubSub ────────────────────────────────────────────────────────────────

  def subscribe(library_id),
    do: Phoenix.PubSub.subscribe(Stashix.PubSub, "health:#{library_id}")

  def broadcast(library_id, msg),
    do: Phoenix.PubSub.broadcast(Stashix.PubSub, "health:#{library_id}", msg)
end
