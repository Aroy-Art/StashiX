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
           {:ok, books, library_uuid, columns} <- read(snap) do
        notes = read_notes(library)
        summary = sync(library, books, notes, Keyword.get(opts, :force, false), progress)
        {:ok, Map.merge(summary, %{stamp: snap.stamp, library_uuid: library_uuid, columns: columns})}
      end

    save_state(library, result)
    Library.SummaryCache.clear()
    result
  end

  defp read(snap) do
    with {:ok, conn} <- Snapshot.open(snap) do
      try do
        with {:ok, books} <- Reader.books(conn),
             {:ok, columns} <- Reader.custom_columns(conn) do
          {:ok, books, Reader.library_uuid(conn), columns}
        end
      after
        Exqlite.Sqlite3.close(conn)
      end
    end
  end

  # Author and series notes; none when the library has no notes database.
  defp read_notes(library) do
    case Snapshot.open_notes(library.id, library.root_path) do
      nil ->
        %{}

      conn ->
        try do
          case Reader.notes(conn) do
            {:ok, notes} -> Map.new(notes, fn {key, html} -> {key, Mapper.html_to_text(html)} end)
            _ -> %{}
          end
        after
          Exqlite.Sqlite3.close(conn)
        end
    end
  end

  defp sync(library, books, notes, force, progress) do
    total = length(books)
    mapped = Enum.map(books, &Mapper.map_book/1)
    series_ids = upsert_series(library, mapped, notes)
    upsert_people(mapped, notes)
    {matches, removed} = match_books(library, mapped)
    covered = covered_book_ids(library)
    now = NaiveDateTime.utc_now(:second)
    read = read_setting(library)

    progress.(:importing, 0, total)
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    results =
      mapped
      |> Task.async_stream(
        fn m ->
          result = process_book(library, m, matches[m.calibre_id], series_ids, force, covered, now, read)
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
      read_marked: Enum.count(results, & &1[:read_marked]),
      read_applied: read && read.key,
      skipped_formats: results |> Enum.flat_map(& &1.skipped) |> Enum.frequencies(),
      errors: for(%{status: :failed, error: error} <- results, do: error) |> Enum.take(20)
    }
  end

  # ── Series ─────────────────────────────────────────────────────────────────

  # `%{calibre series id => series id}`. A series is found by Calibre id when
  # the name still matches, else by name (Calibre renumbers series when it
  # rebuilds its database), else by id (renamed in Calibre).
  defp upsert_series(library, mapped, notes) do
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
        # A note or link sets the summary / URL; without one, a summary
        # written in Stashix stays.
        attrs =
          %{
            name: s.name,
            sort_name: s.sort_name,
            calibre_id: s.calibre_id,
            library_id: library.id,
            deleted_at: nil
          }
          |> put_present(:url, s[:url])
          |> put_present(:summary, notes[{"series", s.calibre_id}])

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

  # ── Authors and publishers ─────────────────────────────────────────────────

  # Created up front, one at a time: books import in parallel, and two books
  # creating the same new author would race on the unique name (the loser's
  # transaction aborts). Authors also take Calibre's sort name here.
  defp upsert_people(mapped, notes) do
    now = NaiveDateTime.utc_now(:second)
    creators = mapped |> Enum.flat_map(& &1.creators) |> Enum.uniq_by(& &1.name)

    creators
    |> Enum.map(&%{id: Ecto.UUID.generate(), name: &1.name, sort_name: &1.sort_name, inserted_at: now, updated_at: now})
    |> Enum.chunk_every(1000)
    |> Enum.each(&Repo.insert_all(Creator, &1, on_conflict: :nothing, conflict_target: :name))

    # Sort name, and the note (as bio) and link Calibre has for the author;
    # creators are shared across libraries, so nothing is cleared.
    for creator <- creators,
        set =
          []
          |> put_present(:sort_name, creator.sort_name)
          |> put_present(:url, creator[:url])
          |> put_present(:bio, notes[{"authors", creator[:calibre_id]}]),
        set != [] do
      name = creator.name

      changed =
        Enum.reduce(set, false, fn {k, v}, acc -> dynamic([c], ^acc or is_nil(field(c, ^k)) or field(c, ^k) != ^v) end)

      Repo.update_all(from(c in Creator, where: c.name == ^name, where: ^changed), set: set)
    end

    mapped
    |> Enum.map(& &1.record.publisher)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.each(&Library.get_or_create_publisher/1)
  end

  defp put_present(acc, _key, nil), do: acc
  defp put_present(acc, _key, ""), do: acc
  defp put_present(acc, key, value) when is_list(acc), do: [{key, value} | acc]
  defp put_present(acc, key, value), do: Map.put(acc, key, value)

  # ── Books ──────────────────────────────────────────────────────────────────

  # `{%{calibre id => existing book}, [removed books]}`, by uuid then id. Books
  # whose Calibre id changes, or that left Calibre, give up their id first so
  # the unique index holds while books take their new ones.
  defp match_books(library, mapped) do
    rows =
      Repo.all(
        from b in Book,
          where: b.library_id == ^library.id and (not is_nil(b.calibre_id) or not is_nil(b.calibre_uuid)),
          select:
            map(b, [
              :id,
              :calibre_id,
              :calibre_uuid,
              :calibre_fingerprint,
              :calibre_fields,
              :calibre_position,
              :deleted_at
            ])
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

  defp process_book(library, m, existing, series_ids, force, covered, now, read) do
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

    # Made here rather than after every book is in, so covers fill in as the
    # sync goes instead of all at the end.
    if preferred && (changed? or files_changed? or not MapSet.member?(covered, book.id)) do
      image = m.cover && Path.join(root, m.cover)
      make_cover(book, preferred.path, if(image && File.regular?(image), do: image))
    end

    status =
      cond do
        is_nil(existing) -> :added
        changed? -> :updated
        true -> :unchanged
      end

    %{status: status, missing: missing, skipped: m.skipped_formats, read_marked: apply_read(read, m, existing, book)}
  rescue
    e ->
      Logger.error("[calibre] book #{m.calibre_id} (#{m.book.title}) failed: #{Exception.message(e)}")
      %{status: :failed, error: "#{m.book.title}: #{Exception.message(e)}", missing: 0, skipped: []}
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
            only_present: true,
            new: is_nil(existing)
          )

        set_publisher(book, m.record.publisher, is_nil(existing))
        book
      end)

    book
  end

  # A new book has no publisher links to clear or compare with.
  defp set_publisher(_book, nil, true = _new?), do: :ok

  defp set_publisher(book, nil, false) do
    Repo.delete_all(from bp in "book_publishers", where: bp.book_id == ^Ecto.UUID.dump!(book.id))
  end

  defp set_publisher(book, name, new?) do
    with {:ok, publisher} <- Library.get_or_create_publisher(name) do
      if new?,
        do: Library.link_publisher_to_book(book.id, publisher.id),
        else: Library.set_book_publisher(book.id, publisher.id)

      if book.series_id, do: Library.link_publisher_to_series(book.series_id, publisher.id)
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
  def preferred_file(files), do: Enum.min_by(files, &Stashix.Media.Formats.reading_rank(&1.format))

  # ── Read status ────────────────────────────────────────────────────────────

  # The user Calibre's read status belongs to (a custom column's value and
  # Calibre's viewer position), when set and the user still exists; the
  # column is optional. `all?` when the setting changed since the last sync:
  # every book's values are applied, not just changed ones.
  defp read_setting(%{calibre_settings: %{"read_user_id" => user_id} = settings} = library)
       when is_binary(user_id) and user_id != "" do
    column = if settings["read_column"] in [nil, ""], do: nil, else: settings["read_column"]

    if Repo.get(Stashix.Accounts.User, user_id) do
      key = "#{user_id}:#{column}"
      %{user_id: user_id, column: column, key: key, all?: (library.calibre_state || %{})["read_applied"] != key}
    end
  end

  defp read_setting(_library), do: nil

  # A value that changed in Calibre (or every value, see `read_setting/1`)
  # moves the user's progress up: the column's yes → read, its number → that
  # percent, the viewer's position → that share. It never lowers it. True
  # when the book was moved.
  defp apply_read(nil, _m, _existing, _book), do: false

  defp apply_read(read, m, existing, book) do
    changed? = fn new, old -> read.all? or is_nil(existing) or new != old end

    column =
      if read.column do
        new = get_in(m.book.calibre_fields, [read.column, "value"])

        if changed?.(new, existing && get_in(existing.calibre_fields || %{}, [read.column, "value"])),
          do: read_progression(new)
      end

    position =
      if (new = m.book.calibre_position) && changed?.(new, existing && existing.calibre_position), do: new

    with p when p > 0 <- Enum.max([column || 0.0, position || 0.0]),
         current = Library.get_progress(read.user_id, book.id),
         true <- is_nil(current) or (current.progression || 0.0) < p do
      page = round(p * max(book.page_count - 1, 0))

      match?(
        {:ok, _},
        Library.update_progress(Stashix.Library.Access.all(), read.user_id, book.id, page, progression: p)
      )
    else
      _ -> false
    end
  end

  defp read_progression(true), do: 1.0
  defp read_progression(n) when is_number(n), do: n |> Kernel./(100) |> max(0.0) |> min(1.0)
  defp read_progression(_value), do: 0.0

  # ── Covers ─────────────────────────────────────────────────────────────────

  defp covered_book_ids(library) do
    from(c in BookCover, join: b in Book, on: b.id == c.book_id, where: b.library_id == ^library.id, select: b.id)
    |> Repo.all()
    |> MapSet.new()
  end

  # A cover that can't be made leaves the book without one; it doesn't stop the sync.
  defp make_cover(book, path, image) do
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
            # Custom column definitions, for the library's settings.
            "columns" =>
              Enum.map(summary.columns, fn c ->
                %{"label" => c.label, "name" => c.name, "type" => c.datatype, "multiple" => c.multiple}
              end),
            "read_applied" => summary.read_applied,
            "summary" => Map.drop(summary, [:stamp, :library_uuid, :columns, :read_applied]),
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
