# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.CalibreFixtures do
  @moduledoc """
  Calibre libraries on disk: a `metadata.db` with Calibre's schema
  (`fixtures/calibre/schema.sql`) and the `<Author>/<Title> (<id>)/` folders
  Calibre keeps the files in.
  """

  alias Exqlite.Sqlite3

  @schema_path Path.join(__DIR__, "fixtures/calibre/schema.sql")
  @external_resource @schema_path
  @schema File.read!(@schema_path)

  @doc """
  Creates a Calibre library at `root` holding `books` (see `add_book/2`).
  Returns `root`.
  """
  def make_library(root, books \\ []) do
    File.mkdir_p!(root)

    with_db(root, fn conn ->
      :ok = Sqlite3.execute(conn, @schema)
      exec(conn, "INSERT INTO library_id (uuid) VALUES (?)", [Ecto.UUID.generate()])
    end)

    Enum.each(books, &add_book(root, &1))
    root
  end

  @doc """
  Adds a book and writes its files. Returns its Calibre id.

  Attributes (all optional): `:id`, `:title`, `:sort`, `:uuid`,
  `:authors` (names, in order), `:series` (`{name, index}`), `:publisher`,
  `:tags`, `:languages` (ISO 639-2 codes), `:rating` (0–10), `:comments`,
  `:identifiers` (`%{type => value}`), `:pubdate`, `:timestamp`,
  `:last_modified` (Calibre's text timestamps), `:formats` (upper-case
  extensions; default `["EPUB"]`), `:files` (`%{format => binary}`; an EPUB
  without one is a one-chapter text EPUB, other formats placeholder bytes),
  `:cover` (write `cover.jpg`, default true).
  """
  def add_book(root, attrs \\ %{}) do
    attrs = Map.new(attrs)
    title = attrs[:title] || "Untitled"
    authors = attrs[:authors] || ["Unknown"]
    formats = attrs[:formats] || ["EPUB"]
    cover? = Map.get(attrs, :cover, true)

    with_db(root, fn conn ->
      exec(
        conn,
        """
        INSERT INTO books (id, title, sort, timestamp, pubdate, series_index, author_sort, path, uuid,
                           has_cover, last_modified)
        VALUES (?, ?, ?, ?, ?, ?, ?, '', ?, ?, ?)
        """,
        [
          attrs[:id],
          title,
          attrs[:sort] || title,
          attrs[:timestamp] || "2024-01-02 03:04:05.000000+00:00",
          attrs[:pubdate] || "0101-01-01 00:00:00+00:00",
          series_index(attrs[:series]),
          Enum.map_join(authors, " & ", &author_sort/1),
          attrs[:uuid] || Ecto.UUID.generate(),
          if(cover?, do: 1, else: 0),
          attrs[:last_modified] || "2024-01-02 03:04:05.000000+00:00"
        ]
      )

      {:ok, id} = Sqlite3.last_insert_rowid(conn)
      dir = "#{safe(hd(authors))}/#{safe(title)} (#{id})"
      name = "#{safe(title)} - #{safe(hd(authors))}"
      exec(conn, "UPDATE books SET path = ? WHERE id = ?", [dir, id])

      for author <- authors do
        author_id = upsert(conn, "authors", author, sort: author_sort(author))
        exec(conn, "INSERT INTO books_authors_link (book, author) VALUES (?, ?)", [id, author_id])
      end

      with {series, _index} <- attrs[:series] do
        series_id = upsert(conn, "series", series, sort: series)
        exec(conn, "INSERT INTO books_series_link (book, series) VALUES (?, ?)", [id, series_id])
      end

      if publisher = attrs[:publisher] do
        publisher_id = upsert(conn, "publishers", publisher)
        exec(conn, "INSERT INTO books_publishers_link (book, publisher) VALUES (?, ?)", [id, publisher_id])
      end

      for tag <- attrs[:tags] || [] do
        tag_id = upsert(conn, "tags", tag)
        exec(conn, "INSERT INTO books_tags_link (book, tag) VALUES (?, ?)", [id, tag_id])
      end

      for {code, order} <- Enum.with_index(attrs[:languages] || []) do
        lang_id = upsert(conn, "languages", code, column: "lang_code")

        exec(conn, "INSERT INTO books_languages_link (book, lang_code, item_order) VALUES (?, ?, ?)", [
          id,
          lang_id,
          order
        ])
      end

      if rating = attrs[:rating] do
        rating_id = upsert(conn, "ratings", rating, column: "rating")
        exec(conn, "INSERT INTO books_ratings_link (book, rating) VALUES (?, ?)", [id, rating_id])
      end

      if comments = attrs[:comments] do
        exec(conn, "INSERT INTO comments (book, text) VALUES (?, ?)", [id, comments])
      end

      for {type, value} <- attrs[:identifiers] || %{} do
        exec(conn, "INSERT INTO identifiers (book, type, val) VALUES (?, ?, ?)", [id, type, value])
      end

      File.mkdir_p!(Path.join(root, dir))
      if cover?, do: File.write!(Path.join([root, dir, "cover.jpg"]), "jpeg")

      for format <- formats do
        path = Path.join([root, dir, "#{name}.#{String.downcase(format)}"])
        write_file(path, format, attrs[:files][format])

        exec(conn, "INSERT INTO data (book, format, uncompressed_size, name) VALUES (?, ?, ?, ?)", [
          id,
          format,
          File.stat!(path).size,
          name
        ])
      end

      id
    end)
  end

  @doc "Runs `sql` with `params` on the library's `metadata.db`."
  def execute(root, sql, params \\ []), do: with_db(root, &exec(&1, sql, params))

  @doc "Rows of `sql` on the library's `metadata.db`, as lists."
  def query(root, sql, params \\ []) do
    with_db(root, fn conn ->
      {:ok, stmt} = Sqlite3.prepare(conn, sql)
      :ok = Sqlite3.bind(stmt, params)
      {:ok, rows} = Sqlite3.fetch_all(conn, stmt)
      :ok = Sqlite3.release(conn, stmt)
      rows
    end)
  end

  defp with_db(root, fun) do
    {:ok, conn} = Sqlite3.open(Path.join(root, "metadata.db"))
    # Per connection only: the file keeps Calibre's rollback journal mode.
    :ok = Sqlite3.execute(conn, "PRAGMA synchronous = OFF; PRAGMA journal_mode = MEMORY")

    try do
      fun.(conn)
    after
      Sqlite3.close(conn)
    end
  end

  defp exec(conn, sql, params) do
    {:ok, stmt} = Sqlite3.prepare(conn, sql)
    :ok = Sqlite3.bind(stmt, params)
    :done = Sqlite3.step(conn, stmt)
    :ok = Sqlite3.release(conn, stmt)
  end

  # Id of the row whose `column` is `value`, inserting it when missing.
  defp upsert(conn, table, value, opts \\ []) do
    column = opts[:column] || "name"

    {:ok, stmt} = Sqlite3.prepare(conn, "SELECT id FROM #{table} WHERE #{column} = ?")
    :ok = Sqlite3.bind(stmt, [value])
    {:ok, rows} = Sqlite3.fetch_all(conn, stmt)
    :ok = Sqlite3.release(conn, stmt)

    case rows do
      [[id]] ->
        id

      [] ->
        if sort = opts[:sort],
          do: exec(conn, "INSERT INTO #{table} (#{column}, sort) VALUES (?, ?)", [value, sort]),
          else: exec(conn, "INSERT INTO #{table} (#{column}) VALUES (?)", [value])

        {:ok, id} = Sqlite3.last_insert_rowid(conn)
        id
    end
  end

  defp write_file(path, "EPUB", nil), do: Stashix.EpubFixtures.make_epub(path, [{:text, "Once upon a time."}])
  defp write_file(path, format, nil), do: File.write!(path, "#{format} placeholder")
  defp write_file(path, _format, data), do: File.write!(path, data)

  defp series_index({_name, index}), do: index / 1
  defp series_index(nil), do: 1.0

  # "Ursula K. Le Guin" → "Guin, Ursula K. Le", like Calibre's default.
  defp author_sort(name) do
    case String.split(name) do
      [_] -> name
      parts -> "#{List.last(parts)}, #{parts |> Enum.drop(-1) |> Enum.join(" ")}"
    end
  end

  # Calibre replaces characters that aren't safe in file names with "_".
  defp safe(name), do: String.replace(name, ~r{[/\\:*?"<>|]}, "_")
end
