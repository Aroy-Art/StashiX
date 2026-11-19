# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Calibre.ReaderTest do
  use ExUnit.Case, async: true

  alias Stashix.Calibre.{Reader, Snapshot}
  alias Stashix.CalibreFixtures

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    root = CalibreFixtures.make_library(Path.join(tmp, "Calibre"))
    %{root: root, id: "lib-#{System.unique_integer([:positive])}"}
  end

  defp read(root, id) do
    {:ok, snap} = Snapshot.take(id, root)
    {:ok, conn} = Snapshot.open(snap)

    try do
      {:ok, books} = Reader.books(conn)
      {books, Reader.library_uuid(conn)}
    after
      Exqlite.Sqlite3.close(conn)
      Snapshot.delete(id)
    end
  end

  test "reads a book with everything attached", %{root: root, id: id} do
    CalibreFixtures.add_book(root, %{
      title: "Good Omens",
      sort: "Good Omens",
      uuid: "11111111-2222-3333-4444-555555555555",
      authors: ["Terry Pratchett", "Neil Gaiman"],
      series: {"Omens", 1.5},
      publisher: "Gollancz",
      tags: ["Fantasy", "Comedy"],
      languages: ["eng", "deu"],
      rating: 9,
      comments: "<p>The world ends on Saturday.</p>",
      identifiers: %{"isbn" => "9780575048003", "goodreads" => "12067"},
      pubdate: "1990-05-01 00:00:00+00:00",
      formats: ["EPUB", "PDF"]
    })

    assert {[book], uuid} = read(root, id)
    assert is_binary(uuid)

    assert %{
             id: 1,
             uuid: "11111111-2222-3333-4444-555555555555",
             title: "Good Omens",
             path: "Terry Pratchett/Good Omens (1)",
             has_cover: true,
             series_index: 1.5,
             author_sort: "Pratchett, Terry & Gaiman, Neil",
             series: %{name: "Omens"},
             publisher: "Gollancz",
             tags: ["Comedy", "Fantasy"],
             languages: ["eng", "deu"],
             rating: 9,
             comments: "<p>The world ends on Saturday.</p>",
             identifiers: %{"isbn" => "9780575048003", "goodreads" => "12067"},
             pubdate: "1990-05-01 00:00:00+00:00"
           } = book

    assert Enum.map(book.authors, & &1.name) == ["Terry Pratchett", "Neil Gaiman"]
    assert hd(book.authors).sort == "Pratchett, Terry"

    assert [%{format: "EPUB", name: "Good Omens - Terry Pratchett"}, %{format: "PDF", size: size}] =
             book.formats

    assert size > 0
  end

  test "a bare book has empty links", %{root: root, id: id} do
    CalibreFixtures.add_book(root, %{title: "Alone", formats: [], cover: false})

    assert {[book], _} = read(root, id)

    assert %{
             series: nil,
             publisher: nil,
             tags: [],
             languages: [],
             rating: nil,
             comments: nil,
             identifiers: %{},
             formats: [],
             has_cover: false
           } = book
  end

  test "books come in id order with their own links", %{root: root, id: id} do
    CalibreFixtures.add_book(root, %{title: "A", tags: ["x"]})
    CalibreFixtures.add_book(root, %{title: "B", tags: ["y", "x"]})

    assert {[a, b], _} = read(root, id)
    assert {a.title, a.tags} == {"A", ["x"]}
    assert {b.title, b.tags} == {"B", ["x", "y"]}
  end
end
