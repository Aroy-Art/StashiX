# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Library.IdentifierSearchTest do
  use Stashix.DataCase, async: true

  alias Stashix.Library
  alias Stashix.Library.Access
  alias Stashix.Metadata.Importer

  setup do
    {:ok, lib} = Library.create_library(%{name: "Shelf", root_path: "/tmp/id-search", kind: :books})

    {:ok, omens} =
      Library.create_book(%{title: "Good Omens", library_id: lib.id, type: "standalone", isbn: "978-0-575-04800-3"})

    {:ok, _} =
      Importer.replace_book_metadata(omens, %{
        external_ids: [%{source: "Goodreads", source_id: "12067"}, %{source: "Google Books", source_id: "AbC"}]
      })

    {:ok, _} = Library.create_book(%{title: "Dune", library_id: lib.id, type: "standalone", isbn: "9780441013593"})
    :ok
  end

  defp search(q) do
    {books, _total} = Library.search_filtered_books(%{q: q}, access: Access.all())
    Enum.map(books, & &1.title)
  end

  test "parses identifier searches" do
    assert Library.identifier_query("isbn:978-0-575-04800-3") == {:isbn, "9780575048003"}
    assert Library.identifier_query("0441013597") == {:isbn, "0441013597"}
    assert Library.identifier_query("978 0441 013593") == {:isbn, "9780441013593"}
    assert Library.identifier_query("Goodreads: 12067") == {:Goodreads, "12067"}
    assert Library.identifier_query("google:AbC") == {:"Google Books", "AbC"}
    assert Library.identifier_query("unknown:1") == nil
    assert Library.identifier_query("dune") == nil
    assert Library.identifier_query("2001") == nil
  end

  test "finds books by ISBN, however it's written" do
    assert search("isbn:9780575048003") == ["Good Omens"]
    assert search("978-0-441-01359-3") == ["Dune"]
  end

  test "finds books by external id, ignoring case" do
    assert search("goodreads:12067") == ["Good Omens"]
    assert search("google:abc") == ["Good Omens"]
    assert search("goodreads:1") == []
  end

  test "other text still searches titles" do
    assert search("dune") == ["Dune"]
  end

  test "matches word prefixes, partial words and typos" do
    {:ok, lib} = Library.create_library(%{name: "Sea", root_path: "/tmp/id-search-sea", kind: :books})

    {:ok, _} =
      Library.create_book(%{
        title: "Seaworthiness: The Forgotten Factor",
        library_id: lib.id,
        type: "standalone"
      })

    for q <- ["seaw", "seaworthin", "seaworthyness", "forgot fact", "SEAW"] do
      assert "Seaworthiness: The Forgotten Factor" in search(q), q
    end

    assert search("seaw dune") == []
    assert search("!:&|()") == []

    assert Library.search_books("seaw", access: Access.all()) |> Enum.map(& &1.title) ==
             ["Seaworthiness: The Forgotten Factor"]

    assert %{books: [%{title: "Seaworthiness: The Forgotten Factor"}]} =
             Library.search_all("seaworthin", access: Access.all())
  end

  test "the API and OPDS search finds identifiers too" do
    assert Library.search_books("9780441013593", access: Access.all()) |> Enum.map(& &1.title) == ["Dune"]
    assert Library.search_books("goodreads:12067", access: Access.all()) |> Enum.map(& &1.title) == ["Good Omens"]
    assert Library.search_books("omens", access: Access.all()) |> Enum.map(& &1.title) == ["Good Omens"]
  end

  test "#label:value searches Calibre custom columns" do
    omens = Stashix.Repo.get_by!(Stashix.Library.Book, title: "Good Omens")

    {:ok, _} =
      Library.update_book(omens, %{
        calibre_fields: %{
          "read" => %{"name" => "Read", "type" => "bool", "value" => true},
          "moods" => %{"name" => "Moods", "type" => "text", "value" => ["Funny", "dark"]}
        }
      })

    assert Library.custom_query("#Read:yes") == {"read", "true"}
    assert Library.custom_query("#moods: funny") == {"moods", "funny"}
    assert Library.custom_query("read:yes") == nil

    assert search("#read:yes") == ["Good Omens"]
    assert search("#read:no") == []
    assert search("#moods:funny") == ["Good Omens"]
    assert search("#nope:x") == []
    assert Library.search_books("#moods:dark", access: Access.all()) |> Enum.map(& &1.title) == ["Good Omens"]
  end
end
