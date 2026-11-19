# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Calibre.Sync do
  @moduledoc """
  Mirrors a Calibre library (`source: :calibre`) into Postgres.

  Every sync reads the whole database from a snapshot and maps each book
  (`Stashix.Calibre.Mapper`); a book is only rewritten when its fingerprint
  changed (D5). Calibre owns every field it maps: those are overwritten
  whatever the book's `locked_fields` say, and Stashix-only fields are never
  touched (D7).

  Books are found by Calibre uuid, then id (D6). A book is visible while it
  is in Calibre and at least one of its files is on disk: a file Calibre
  names but that isn't there (yet — rsync may still be copying it) is kept
  as a `book_files` row with `deleted_at`, the "missing" the Health page
  lists, and comes back on the next sync that finds it (D10). Formats
  removed in Calibre lose their row; books removed from Calibre are
  soft-deleted.

  Files are only read (hash, page count, content kind) when new or changed
  on disk; covers are made from Calibre's `cover.jpg`, or the book's first
  page without one.
  """

  import Ecto.Query
  require Logger

  alias Stashix.{Library, Repo, Scanner}
  alias Stashix.Calibre.{Mapper, Reader, Snapshot}
  alias Stashix.Library.{Book, BookCover, BookFile, Creator, Series}
  alias Stashix.Media.ContentKind
  alias Stashix.Metadata.Importer

  @concurrency 4

  # The format a multi-format book opens in, best first (D9).
  @preferred [:epub, :azw3, :mobi, :azw, :fb2, :fbz, :pdf, :cbz, :cbr, :cb7]

  @doc """
  Syncs `library` with its Calibre database. Returns `{:ok, summary}` or
  `{:error, reason}`; either way the outcome is stored in
  `library.calibre_state`.

  Options: `force: true` rewrites every book (fingerprints ignored);
  `progress: fn phase, done, total -> … end`.
  """
  def run(%Library.Library{source: :calibre} = library, opts \\ []) do
    progress = Keyword.get(opts, :progress, fn _phase, _done, _total -> :ok end)
    progress.(:collecting, 0, 0)

    result =
      with {:ok, snap} <- Snapshot.take(library.id, library.root_path),
           {:ok, books, library_uuid} <- read(snap) do
        summary = sync(library, books, Keyword.get(opts, :force, false), progress)
        {:ok, Map.merge(summary, %{stamp: snap.stamp, library_uuid: library_uuid})}
      end

    save_state(library, result)
    Library.SummaryCache.clear()
    result
  end

  defp read(snap) do
    with {:ok, conn} <- Snapshot.open(snap) do
      try do
        with {:ok, books} <- Reader.books(conn), do: {:ok, books, Reader.library_uuid(conn)}
      after
        Exqlite.Sqlite3.close(conn)
      end
    end
  end

  defp sync(library, books, force, progress) do
    total = length(books)
    mapped = Enum.map(books, &Mapper.map_book/1)
    series_ids = upsert_series(library, mapped)
    {matches, removed} = match_books(library, mapped)
    covered = covered_book_ids(library)
    now = NaiveDateTime.utc_now(:second)

    progress.(:importing, 0, total)
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    results =
      mapped
      |> Task.async_stream(
        fn m ->
          result = process_book(library, m, matches[m.calibre_id], series_ids, force, covered, now)
          done = Agent.get_and_update(counter, &{&1 + 1, &1 + 1})
          progress.(:importing, done, total)
          result
        end,
        max_concurrency: @concurrency,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    Agent.stop(counter)

    remove_books(removed, now)
    make_covers(results, progress)
    Library.mark_empty_series_deleted(library.id)
    Library.update_series_counts(library.id)

    %{
      books: total,
      added: Enum.count(results, &(&1.status == :added)),
      updated: Enum.count(results, &(&1.status == :updated)),
      unchanged: Enum.count(results, &(&1.status == :unchanged)),
      failed: Enum.count(results, &(&1.status == :failed)),
      removed: length(removed),
      missing_files: Enum.sum_by(results, & &1.missing),
      skipped_formats: results |> Enum.flat_map(& &1.skipped) |> Enum.frequencies(),
      errors: for(%{status: :failed, error: error} <- results, do: error) |> Enum.take(20)
    }
  end

  # ── Series ─────────────────────────────────────────────────────────────────

  # `%{calibre series id => series id}`. A series is found by Calibre id when
  # the name still matches, else by name (Calibre renumbers series when it
  # rebuilds its database), else by id (renamed in Calibre).
  defp upsert_series(library, mapped) do
    wanted = mapped |> Enum.map(& &1.series) |> Enum.reject(&is_nil/1) |> Enum.uniq_by(& &1.calibre_id)
    rows = Repo.all(from s in Series, where: s.library_id == ^library.id and not is_nil(s.calibre_id))
    by_id = Map.new(rows, &{&1.calibre_id, &1})
    by_name = Map.new(rows, &{String.downcase(&1.name), &1})

    {pairs, _claimed} =
      Enum.map_reduce(wanted, MapSet.new(), fn s, claimed ->
        free = fn row -> row && not MapSet.member?(claimed, row.id) && row end
        same_id = free.(by_id[s.calibre_id])

        row =
          (same_id && String.downcase(same_id.name) == String.downcase(s.name) && same_id) ||
            free.(by_name[String.downcase(s.name)]) || same_id

        {{s, row}, if(row, do: MapSet.put(claimed, row.id), else: claimed)}
      end)

    Repo.transaction(fn ->
      # Free the ids that move before taking them, for the unique index.
      moving = for {s, %{calibre_id: old} = row} <- pairs, old != s.calibre_id, do: row.id
      claimed = for {_s, row} <- pairs, row, do: row.id
      gone = for row <- rows, row.id not in claimed, do: row.id
      Repo.update_all(from(s in Series, where: s.id in ^(moving ++ gone)), set: [calibre_id: nil])

      Map.new(pairs, fn {s, row} ->
        attrs = %{
          name: s.name,
          sort_name: s.sort_name,
          calibre_id: s.calibre_id,
          library_id: library.id,
          deleted_at: nil
        }

        series =
          case row do
            nil -> Repo.insert!(Series.changeset(%Series{}, attrs))
            row -> Repo.update!(Series.changeset(%{row | calibre_id: nil}, attrs))
          end

        {s.calibre_id, series.id}
      end)
    end)
    |> then(fn {:ok, ids} -> ids end)
  end

  # ── Books ──────────────────────────────────────────────────────────────────

  # `{%{calibre id => existing book}, [removed books]}`, by uuid then id. Books
  # whose Calibre id changes, or that left Calibre, give up their id first so
  # the unique index holds while books take their new ones.
  defp match_books(library, mapped) do
    rows =
      Repo.all(
        from b in Book,
          where: b.library_id == ^library.id and (not is_nil(b.calibre_id) or not is_nil(b.calibre_uuid)),
          select: map(b, [:id, :calibre_id, :calibre_uuid, :calibre_fingerprint, :deleted_at])
      )

    by_uuid = Map.new(rows, &{&1.calibre_uuid, &1})
    by_id = Map.new(rows, &{&1.calibre_id, &1})
    uuids = MapSet.new(mapped, & &1.calibre_uuid)

    matches =
      Map.new(mapped, fn m ->
        # An id match only counts when that book's uuid isn't still in Calibre
        # under another id.
        row =
          by_uuid[m.calibre_uuid] || with(%{} = row <- by_id[m.calibre_id], false <- row.calibre_uuid in uuids, do: row)

        {m.calibre_id, row || nil}
      end)

    matched = for {_id, row} <- matches, row, into: MapSet.new(), do: row.id
    removed = Enum.reject(rows, &MapSet.member?(matched, &1.id))
    moving = for {id, row} <- matches, row, row.calibre_id != id, do: row.id

    if moving != [] or removed != [] do
      ids = moving ++ Enum.map(removed, & &1.id)
      Repo.update_all(from(b in Book, where: b.id in ^ids), set: [calibre_id: nil])
    end

    {matches, Enum.reject(removed, & &1.deleted_at)}
  end

  defp process_book(library, m, existing, series_ids, force, covered, now) do
    root = library.root_path
    # A book that gave up its Calibre id (`match_books/2`) is rewritten to take it back.
    changed? =
      force or is_nil(existing) or existing.calibre_fingerprint != m.fingerprint or
        existing.calibre_id != m.calibre_id

    present? = Enum.any?(m.files, &File.regular?(Path.join(root, &1.path)))
    deleted_at = if present?, do: nil, else: (existing && existing.deleted_at) || now

    book = upsert_book(library, m, existing, series_ids, changed?, deleted_at)
    {files, files_changed?, missing} = sync_files(book, m, root, now)
    preferred = preferred_file(files)

    book =
      Repo.update!(
        Ecto.Changeset.change(book,
          deleted_at: if(preferred, do: nil, else: book.deleted_at || now),
          page_count: (preferred && preferred.page_count) || 0
        )
      )

    cover =
      if preferred && (changed? or files_changed? or not MapSet.member?(covered, book.id)) do
        image = m.cover && Path.join(root, m.cover)
        {book, preferred.path, if(image && File.regular?(image), do: image)}
      end

    status =
      cond do
        is_nil(existing) -> :added
        changed? -> :updated
        true -> :unchanged
      end

    %{status: status, cover: cover, missing: missing, skipped: m.skipped_formats}
  rescue
    e ->
      Logger.error("[calibre] book #{m.calibre_id} (#{m.book.title}) failed: #{Exception.message(e)}")
      %{status: :failed, error: "#{m.book.title}: #{Exception.message(e)}", cover: nil, missing: 0, skipped: []}
  end

  defp upsert_book(_library, _m, existing, _series_ids, false, _deleted_at), do: Repo.get!(Book, existing.id)

  defp upsert_book(library, m, existing, series_ids, true, deleted_at) do
    attrs =
      m.book
      |> Map.reject(fn {key, value} -> key == :language and is_nil(value) end)
      |> Map.merge(%{
        library_id: library.id,
        series_id: m.series && series_ids[m.series.calibre_id],
        calibre_id: m.calibre_id,
        calibre_uuid: m.calibre_uuid,
        calibre_fingerprint: m.fingerprint,
        deleted_at: deleted_at
      })

    {:ok, book} =
      Repo.transaction(fn ->
        book =
          case existing do
            nil -> Repo.insert!(Book.changeset(%Book{}, attrs))
            %{id: id} -> Repo.update!(Book.changeset(Repo.get!(Book, id), attrs))
          end

        {:ok, :ok} =
          Importer.replace_book_metadata(book, Map.take(m.record, [:tags, :credits, :external_ids, :urls]),
            only_present: true
          )

        set_publisher(book, m.record.publisher)
        set_creator_sort_names(m.creators)
        book
      end)

    book
  end

  defp set_publisher(book, nil) do
    Repo.delete_all(from bp in "book_publishers", where: bp.book_id == ^Ecto.UUID.dump!(book.id))
  end

  defp set_publisher(book, name) do
    with {:ok, publisher} <- Library.get_or_create_publisher(name) do
      Library.set_book_publisher(book.id, publisher.id)
      if book.series_id, do: Library.link_publisher_to_series(book.series_id, publisher.id)
    end
  end

  defp set_creator_sort_names(creators) do
    for %{name: name, sort_name: sort} <- creators, sort do
      Repo.update_all(
        from(c in Creator, where: c.name == ^name and (is_nil(c.sort_name) or c.sort_name != ^sort)),
        set: [sort_name: sort]
      )
    end
  end

  defp remove_books([], _now), do: :ok

  defp remove_books(removed, now) do
    ids = Enum.map(removed, & &1.id)
    Repo.update_all(from(f in BookFile, where: f.book_id in ^ids and is_nil(f.deleted_at)), set: [deleted_at: now])
    Repo.update_all(from(b in Book, where: b.id in ^ids), set: [deleted_at: now])
  end

  # ── Files ──────────────────────────────────────────────────────────────────

  # `{present files, anything changed?, missing count}`.
  defp sync_files(book, m, root, now) do
    rows = Repo.all(from f in BookFile, where: f.book_id == ^book.id)
    by_path = Map.new(rows, &{&1.path, &1})
    wanted = Enum.map(m.files, &Map.put(&1, :abs, Path.join(root, &1.path)))

    stale = Enum.reject(rows, fn row -> Enum.any?(wanted, &(&1.abs == row.path)) end)
    Enum.each(stale, &Repo.delete!/1)

    {files, changes} =
      Enum.map_reduce(wanted, stale != [], fn file, changed ->
        row = by_path[file.abs] || Repo.get_by(BookFile, path: file.abs)
        {result, did_change} = sync_file(book, file, row, now)
        {result, changed or did_change}
      end)

    present = for {:present, row} <- files, do: row
    {present, changes, Enum.count(files, &match?({:missing, _}, &1))}
  end

  defp sync_file(book, file, row, now) do
    case File.stat(file.abs) do
      {:ok, %File.Stat{type: :regular} = stat} ->
        modified = NaiveDateTime.from_erl!(stat.mtime)

        if row && row.book_id == book.id && is_nil(row.deleted_at) && row.file_size == stat.size &&
             row.last_modified == modified do
          {{:present, row}, false}
        else
          attrs = %{
            book_id: book.id,
            path: file.abs,
            format: file.format,
            file_size: stat.size,
            file_hash: Scanner.compute_hash(file.abs, stat.size),
            last_modified: modified,
            page_count: Scanner.page_count(file.abs),
            content_kind: ContentKind.detect(file.abs),
            deleted_at: nil
          }

          {{:present, save_file(row, attrs)}, true}
        end

      _ ->
        attrs = %{book_id: book.id, path: file.abs, format: file.format, file_size: file.size, deleted_at: now}

        case row do
          %{deleted_at: %NaiveDateTime{}, book_id: id} when id == book.id -> {{:missing, row}, false}
          _ -> {{:missing, save_file(row, attrs)}, row != nil}
        end
    end
  end

  defp save_file(nil, attrs), do: Repo.insert!(BookFile.changeset(%BookFile{}, attrs))
  defp save_file(row, attrs), do: Repo.update!(BookFile.changeset(row, attrs))

  @doc "The file a multi-format book opens in (D9)."
  def preferred_file([]), do: nil
  def preferred_file(files), do: Enum.min_by(files, &(Enum.find_index(@preferred, fn f -> f == &1.format end) || 99))

  # ── Covers ─────────────────────────────────────────────────────────────────

  defp covered_book_ids(library) do
    from(c in BookCover, join: b in Book, on: b.id == c.book_id, where: b.library_id == ^library.id, select: b.id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp make_covers(results, progress) do
    jobs = for %{cover: {_, _, _} = job} <- results, do: job
    total = length(jobs)
    if total > 0, do: progress.(:thumbnails, 0, total)

    jobs
    |> Task.async_stream(&make_cover/1,
      max_concurrency: @concurrency,
      ordered: false,
      timeout: 120_000
    )
    |> Stream.with_index(1)
    |> Enum.each(fn {_, n} -> progress.(:thumbnails, n, total) end)
  end

  # A cover that can't be made leaves the book without one; it doesn't stop the sync.
  defp make_cover({book, path, image}) do
    Scanner.generate_thumbnail(book, path, image)
  rescue
    e -> Logger.warning("[calibre] cover for #{book.title} failed: #{Exception.message(e)}")
  end

  # ── State ──────────────────────────────────────────────────────────────────

  defp save_state(library, result) do
    now = NaiveDateTime.utc_now(:second) |> NaiveDateTime.to_iso8601()

    state =
      case result do
        {:ok, summary} ->
          %{
            "synced_at" => now,
            "stamp" => summary.stamp,
            "library_uuid" => summary.library_uuid,
            "summary" => Map.drop(summary, [:stamp, :library_uuid]),
            "error" => nil
          }

        {:error, reason} ->
          (library.calibre_state || %{})
          |> Map.put("error", error_text(reason))
          |> Map.put("failed_at", now)
      end

    Repo.update_all(from(l in Library.Library, where: l.id == ^library.id), set: [calibre_state: state])
  end

  @doc "A sync error as one line for the admin page."
  def error_text(:no_database), do: "No metadata.db in the library folder"
  def error_text(:busy), do: "metadata.db kept changing while it was copied (Calibre or a sync still writing)"
  def error_text(:corrupt), do: "metadata.db is not a readable SQLite database"
  def error_text({:unsupported, missing}), do: "Unsupported Calibre database, missing: #{Enum.join(missing, ", ")}"
  def error_text(reason), do: inspect(reason)
end
