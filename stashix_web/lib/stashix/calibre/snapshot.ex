# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Calibre.Snapshot do
  @moduledoc """
  A private copy of a Calibre library's `metadata.db`.

  Stashix never reads Calibre's own file: a read transaction would hold a
  shared lock that makes Calibre fail with "database is locked", and rsync
  replaces the file by renaming a new one over it. So a sync copies the file
  to `<calibre cache dir>/<library id>.db` and reads the copy.

  A copy is only kept when it is whole: no `metadata.db-journal` (a write in
  progress) and the same stamp before and after copying. The stamp holds
  inode, size and mtime plus the file change counter from the SQLite header,
  which every commit bumps, so even a same-size write in the same second is
  seen.
  """

  alias Exqlite.Sqlite3

  @db "metadata.db"
  @attempts 3
  @retry_ms 500

  # Tables and columns the reader needs. Checked instead of `user_version`, so
  # a newer Calibre that only adds things keeps working.
  @required %{
    "books" => ~w(id title sort timestamp pubdate series_index author_sort path uuid has_cover last_modified),
    "data" => ~w(book format name uncompressed_size),
    "authors" => ~w(id name sort link),
    "books_authors_link" => ~w(id book author),
    "series" => ~w(id name sort),
    "books_series_link" => ~w(book series),
    "publishers" => ~w(id name),
    "books_publishers_link" => ~w(book publisher),
    "tags" => ~w(id name),
    "books_tags_link" => ~w(book tag),
    "languages" => ~w(id lang_code),
    "books_languages_link" => ~w(book lang_code item_order),
    "ratings" => ~w(id rating),
    "books_ratings_link" => ~w(book rating),
    "comments" => ~w(book text),
    "identifiers" => ~w(book type val)
  }

  defstruct [:path, :stamp]

  @type stamp :: %{inode: integer, size: integer, mtime: integer, counter: integer}
  @type t :: %__MODULE__{path: String.t(), stamp: stamp}

  @doc "Path of the Calibre database in a library root."
  def db_path(root), do: Path.join(root, @db)

  @doc "Whether `root` holds a Calibre library."
  def calibre_library?(root), do: File.regular?(db_path(root))

  @doc """
  The stamp of the live database, to compare with the last synced one.
  `{:error, :busy}` while Calibre is writing (a journal exists).
  """
  @spec stamp(String.t()) :: {:ok, stamp} | {:error, :no_database | :busy | term}
  def stamp(root), do: stamp_file(db_path(root))

  @doc """
  Copies the live database for `library_id` and checks the copy. Retries a
  few times when Calibre or rsync changes the file meanwhile.

  Options (for tests): `:retry_ms`, `:copy` (a `File.copy/2` stand-in).
  """
  @spec take(String.t(), String.t(), keyword) :: {:ok, t} | {:error, term}
  def take(library_id, root, opts \\ []), do: take(library_id, root, opts, @attempts)

  defp take(_library_id, _root, _opts, 0), do: {:error, :busy}

  defp take(library_id, root, opts, attempts) do
    source = db_path(root)
    target = path(library_id)
    tmp = target <> ".tmp"

    with {:ok, before} <- stamp_file(source),
         :ok <- File.mkdir_p(Path.dirname(target)),
         {:ok, _} <- Keyword.get(opts, :copy, &File.copy/2).(source, tmp),
         {:ok, ^before} <- stamp_file(source),
         {:ok, %{counter: counter}} when counter == before.counter <- stamp_file(tmp),
         :ok <- check(tmp),
         :ok <- File.rename(tmp, target) do
      {:ok, %__MODULE__{path: target, stamp: before}}
    else
      # Being written, or changed while we copied: try again shortly.
      result when result == {:error, :busy} or elem(result, 0) == :ok ->
        File.rm(tmp)
        Process.sleep(Keyword.get(opts, :retry_ms, @retry_ms))
        take(library_id, root, opts, attempts - 1)

      {:error, reason} ->
        File.rm(tmp)
        {:error, reason}
    end
  end

  @doc "Opens a snapshot read-only. The caller closes it with `Exqlite.Sqlite3.close/1`."
  def open(%__MODULE__{path: path}), do: Sqlite3.open(path, mode: :readonly)

  @doc "Removes a library's snapshot (library deleted, or switched to folders)."
  def delete(library_id) do
    File.rm(path(library_id))
    :ok
  end

  @doc "Where `library_id`'s snapshot lives."
  def path(library_id), do: Path.join(dir(), "#{library_id}.db")

  defp dir do
    Application.get_env(:stashix, :calibre_cache_dir) ||
      Path.join(Path.dirname(Application.fetch_env!(:stashix, :page_cache_dir)), "calibre")
  end

  defp stamp_file(path) do
    with {:ok, %File.Stat{type: :regular} = stat} <- File.stat(path, time: :posix),
         false <- File.exists?(path <> "-journal"),
         {:ok, counter} <- change_counter(path) do
      {:ok, %{inode: stat.inode, size: stat.size, mtime: stat.mtime, counter: counter}}
    else
      {:error, :enoent} -> {:error, :no_database}
      true -> {:error, :busy}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :corrupt}
    end
  end

  # Bytes 24..27 of the SQLite header: the file change counter.
  defp change_counter(path) do
    with {:ok, io} <- File.open(path, [:read, :binary]) do
      try do
        case :file.pread(io, 0, 28) do
          {:ok, <<"SQLite format 3", 0, _::binary-size(8), counter::32>>} -> {:ok, counter}
          _ -> {:error, :corrupt}
        end
      after
        File.close(io)
      end
    end
  end

  defp check(path) do
    with {:ok, conn} <- Sqlite3.open(path, mode: :readonly) do
      try do
        with {:ok, [["ok"]]} <- rows(conn, "PRAGMA quick_check"),
             [] <- missing_columns(conn) do
          :ok
        else
          {:ok, _problems} -> {:error, :corrupt}
          {:error, _} -> {:error, :corrupt}
          missing when is_list(missing) -> {:error, {:unsupported, missing}}
        end
      after
        Sqlite3.close(conn)
      end
    end
  end

  # `["books.uuid", "identifiers", …]` for what the reader needs but the
  # database lacks.
  defp missing_columns(conn) do
    Enum.flat_map(@required, fn {table, columns} ->
      case rows(conn, "SELECT name FROM pragma_table_info('#{table}')") do
        {:ok, []} -> [table]
        {:ok, rows} -> Enum.map(columns -- List.flatten(rows), &"#{table}.#{&1}")
        _ -> [table]
      end
    end)
    |> Enum.sort()
  end

  @doc false
  def rows(conn, sql, params \\ []) do
    with {:ok, stmt} <- Sqlite3.prepare(conn, sql) do
      try do
        with :ok <- Sqlite3.bind(stmt, params), do: Sqlite3.fetch_all(conn, stmt)
      after
        Sqlite3.release(conn, stmt)
      end
    end
  end
end
