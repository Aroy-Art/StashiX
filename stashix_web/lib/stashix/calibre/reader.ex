# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Calibre.Reader do
  @moduledoc """
  Reads every book out of an open Calibre database (a
  `Stashix.Calibre.Snapshot`) as plain maps: one query per table, joined
  here. Values stay as Calibre stores them; `Stashix.Calibre.Mapper` turns
  them into Stashix attributes.

  Each book:

      %{id: 12, uuid: "…", title: "Dune", sort: "Dune", path: "Frank Herbert/Dune (12)",
        has_cover: true, timestamp: "2024-…+00:00", pubdate: "…", last_modified: "…",
        series_index: 1.0, author_sort: "Herbert, Frank",
        authors: [%{id: 3, name: "Frank Herbert", sort: "Herbert, Frank", link: ""}],
        series: %{id: 5, name: "Dune", sort: "Dune"} | nil,
        publisher: "Ace" | nil, tags: ["SF"], languages: ["eng"], rating: 8 | nil,
        comments: "<p>…</p>" | nil, identifiers: %{"isbn" => "…"},
        formats: [%{format: "EPUB", name: "Dune - Frank Herbert", size: 123}],
        custom: %{"read" => %{name: "Read", datatype: "bool", multiple: false, values: [1]}}}

  `custom` holds the book's custom column values as Calibre stores them, by
  label: a list of values, `{name, index}` pairs for series columns.
  """

  import Stashix.Calibre.Snapshot, only: [rows: 2]

  @doc "All books, by Calibre id."
  @spec books(Exqlite.Sqlite3.db()) :: {:ok, [map]} | {:error, term}
  def books(conn) do
    with {:ok, books} <-
           rows(conn, """
           SELECT id, uuid, title, sort, path, has_cover, timestamp, pubdate, last_modified,
                  series_index, author_sort
           FROM books ORDER BY id
           """),
         {:ok, authors} <-
           rows(conn, """
           SELECT l.book, a.id, a.name, a.sort, a.link
           FROM books_authors_link l JOIN authors a ON a.id = l.author
           ORDER BY l.book, l.id
           """),
         {:ok, series} <-
           rows(conn, """
           SELECT l.book, s.id, s.name, s.sort, s.link
           FROM books_series_link l JOIN series s ON s.id = l.series
           """),
         {:ok, publishers} <-
           rows(conn, """
           SELECT l.book, p.name
           FROM books_publishers_link l JOIN publishers p ON p.id = l.publisher
           ORDER BY l.book, l.id
           """),
         {:ok, tags} <-
           rows(conn, """
           SELECT l.book, t.name
           FROM books_tags_link l JOIN tags t ON t.id = l.tag
           ORDER BY l.book, t.name
           """),
         {:ok, languages} <-
           rows(conn, """
           SELECT l.book, g.lang_code
           FROM books_languages_link l JOIN languages g ON g.id = l.lang_code
           ORDER BY l.book, l.item_order
           """),
         {:ok, ratings} <-
           rows(conn, """
           SELECT l.book, r.rating
           FROM books_ratings_link l JOIN ratings r ON r.id = l.rating
           """),
         {:ok, comments} <- rows(conn, "SELECT book, text FROM comments"),
         {:ok, identifiers} <- rows(conn, "SELECT book, type, val FROM identifiers ORDER BY book, type"),
         {:ok, formats} <-
           rows(conn, "SELECT book, format, name, uncompressed_size FROM data ORDER BY book, format"),
         {:ok, columns} <- custom_columns(conn),
         {:ok, custom} <- custom_values(conn, columns) do
      authors = group(authors, fn [id, name, sort, link] -> %{id: id, name: name, sort: sort, link: link} end)
      series = first(series, fn [id, name, sort, link] -> %{id: id, name: name, sort: sort, link: link} end)
      publishers = first(publishers, fn [name] -> name end)
      tags = group(tags, fn [name] -> name end)
      languages = group(languages, fn [code] -> code end)
      ratings = first(ratings, fn [rating] -> rating end)
      comments = first(comments, fn [text] -> text end)
      identifiers = group(identifiers, fn [type, val] -> {type, val} end)

      formats =
        group(formats, fn [format, name, size] -> %{format: String.upcase(format), name: name, size: size} end)

      {:ok,
       Enum.map(books, fn [id, uuid, title, sort, path, has_cover, timestamp, pubdate, modified, index, author_sort] ->
         %{
           id: id,
           uuid: uuid,
           title: title,
           sort: sort,
           path: path,
           has_cover: has_cover in [1, true],
           timestamp: timestamp,
           pubdate: pubdate,
           last_modified: modified,
           series_index: index,
           author_sort: author_sort,
           authors: Map.get(authors, id, []),
           series: Map.get(series, id),
           publisher: Map.get(publishers, id),
           tags: Map.get(tags, id, []),
           languages: Map.get(languages, id, []),
           rating: Map.get(ratings, id),
           comments: Map.get(comments, id),
           identifiers: Map.new(Map.get(identifiers, id, [])),
           formats: Map.get(formats, id, []),
           custom: Map.get(custom, id, %{})
         }
       end)}
    end
  end

  # Computed (composite) columns have no table, and columns deleted in Calibre
  # wait for a restart with `mark_for_delete`.
  @doc "The library's custom columns: `%{id, label, name, datatype, multiple, normalized}`."
  def custom_columns(conn) do
    with {:ok, rows} <-
           rows(conn, """
           SELECT id, label, name, datatype, is_multiple, normalized FROM custom_columns
           WHERE mark_for_delete = 0 AND datatype != 'composite' ORDER BY id
           """) do
      {:ok,
       Enum.map(rows, fn [id, label, name, datatype, multiple, normalized] ->
         %{
           id: id,
           label: label,
           name: name,
           datatype: datatype,
           multiple: multiple in [1, true],
           normalized: normalized in [1, true]
         }
       end)}
    end
  end

  # `%{book_id => %{label => %{name, datatype, multiple, values}}}`.
  defp custom_values(conn, columns) do
    Enum.reduce_while(columns, {:ok, %{}}, fn column, {:ok, acc} ->
      case column_rows(conn, column) do
        {:ok, rows} ->
          acc =
            rows
            |> Enum.group_by(&hd/1, fn [_book | value] -> column_value(column, value) end)
            |> Enum.reduce(acc, fn {book, values}, acc ->
              entry = %{name: column.name, datatype: column.datatype, multiple: column.multiple, values: values}
              Map.update(acc, book, %{column.label => entry}, &Map.put(&1, column.label, entry))
            end)

          {:cont, {:ok, acc}}

        # A column whose tables are missing is skipped, not fatal.
        {:error, _} ->
          {:cont, {:ok, acc}}
      end
    end)
  end

  defp column_rows(conn, %{id: id, normalized: true, datatype: "series"}) do
    rows(conn, """
    SELECT l.book, v.value, l.extra FROM books_custom_column_#{id}_link l
    JOIN custom_column_#{id} v ON v.id = l.value ORDER BY l.book, l.id
    """)
  end

  defp column_rows(conn, %{id: id, normalized: true}) do
    rows(conn, """
    SELECT l.book, v.value FROM books_custom_column_#{id}_link l
    JOIN custom_column_#{id} v ON v.id = l.value ORDER BY l.book, l.id
    """)
  end

  defp column_rows(conn, %{id: id}), do: rows(conn, "SELECT book, value FROM custom_column_#{id} ORDER BY book")

  defp column_value(%{datatype: "series"}, [name, index]), do: {name, index}
  defp column_value(_column, [value]), do: value

  @doc """
  Calibre's notes (`.calnotes/notes.db`, opened like the library's
  database) for authors and series, as `%{{"authors" | "series", id} => html}`.
  """
  def notes(conn) do
    case rows(conn, "SELECT colname, item, doc FROM notes WHERE colname IN ('authors', 'series') AND doc != ''") do
      {:ok, rows} -> {:ok, Map.new(rows, fn [col, item, doc] -> {{String.downcase(col), item}, doc} end)}
      error -> error
    end
  end

  @doc "The library's own uuid (`library_id` table), or nil."
  def library_uuid(conn) do
    case rows(conn, "SELECT uuid FROM library_id LIMIT 1") do
      {:ok, [[uuid]]} -> uuid
      _ -> nil
    end
  end

  # `%{book_id => [value]}` in row order.
  defp group(rows, fun) do
    rows
    |> Enum.group_by(&hd/1, &fun.(tl(&1)))
  end

  # `%{book_id => value}` for one-per-book links (the first row wins).
  defp first(rows, fun) do
    Enum.reduce(rows, %{}, fn [book | rest], acc -> Map.put_new(acc, book, fun.(rest)) end)
  end
end
