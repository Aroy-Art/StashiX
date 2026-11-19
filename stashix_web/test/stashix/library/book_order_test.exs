# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Library.BookOrderTest do
  use Stashix.DataCase, async: true

  alias Stashix.Library
  alias Stashix.Library.Access
  alias Stashix.Metadata.Importer

  setup do
    {:ok, lib} = Library.create_library(%{name: "Shelf", root_path: "/tmp/book-order", kind: :books})

    book = fn title, attrs, author ->
      {:ok, b} =
        Library.create_book(Map.merge(%{title: title, library_id: lib.id, type: "standalone"}, attrs))

      {:ok, _} = Importer.replace_book_metadata(b, %{credits: [%{creator: author, roles: ["Writer"]}]})
      b
    end

    hobbit = book.("The Hobbit", %{sort_title: "Hobbit, The", added_at: ~N[2020-01-01 00:00:00]}, "J. R. R. Tolkien")
    dune = book.("Dune", %{added_at: ~N[2024-01-01 00:00:00]}, "Frank Herbert")
    anathem = book.("Anathem", %{}, "Neal Stephenson")

    Stashix.Repo.update_all(Stashix.Library.Creator, set: [sort_name: nil])

    for {name, sort} <- [{"J. R. R. Tolkien", "Tolkien, J. R. R."}, {"Frank Herbert", "Herbert, Frank"}] do
      Stashix.Repo.update_all(from(c in Stashix.Library.Creator, where: c.name == ^name), set: [sort_name: sort])
    end

    %{lib: lib, hobbit: hobbit, dune: dune, anathem: anathem}
  end

  defp titles(lib, sort) do
    [access: Access.all(), library_id: lib.id, sort: sort] |> Library.list_all_books() |> Enum.map(& &1.title)
  end

  test "titles sort by their sort title", %{lib: lib} do
    assert titles(lib, "title_asc") == ["Anathem", "Dune", "The Hobbit"]
    assert titles(lib, "title_desc") == ["The Hobbit", "Dune", "Anathem"]
  end

  test "authors sort by the writer's sort name, then by name", %{lib: lib} do
    # Herbert, Neal Stephenson (no sort name), Tolkien.
    assert titles(lib, "author_asc") == ["Dune", "Anathem", "The Hobbit"]
  end

  test "date added prefers the library's own date", %{lib: lib} do
    # Anathem has no added_at: it falls back to when the row was made (now).
    assert titles(lib, "added_desc") == ["Anathem", "Dune", "The Hobbit"]
    assert Enum.map(Library.recent_books(Access.all(), lib.id), & &1.title) == ["Anathem", "Dune", "The Hobbit"]
  end

  test "the library page's books tab orders the same way", %{lib: lib} do
    books = Library.list_books(lib.id, access: Access.all(), type: "standalone", sort: "title_asc")
    assert Enum.map(books, & &1.title) == ["Anathem", "Dune", "The Hobbit"]
  end
end
