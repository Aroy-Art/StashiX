# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Library.LibraryKindTest do
  use Stashix.DataCase, async: true

  alias Stashix.{Accounts, Library, Repo}
  alias Stashix.Library.{Access, Book, BookFile}

  defp library(kind) do
    {:ok, lib} =
      Library.create_library(%{
        name: "#{kind}",
        root_path: "/tmp/#{kind}-#{System.unique_integer([:positive])}",
        kind: kind
      })

    lib
  end

  test "libraries are comics unless made as books" do
    {:ok, lib} = Library.create_library(%{name: "Plain", root_path: "/tmp/plain"})
    assert lib.kind == :comics
    assert library(:books).kind == :books
    assert {:error, _} = Library.create_library(%{name: "Odd", root_path: "/tmp/odd", kind: "films"})
  end

  describe "reader_kind/2 when the file's kind is unknown" do
    test "a books library opens text formats in the text reader" do
      books = library(:books)
      assert Library.reader_kind(%Book{library_id: books.id}, %BookFile{format: :pdf}) == :text
      assert Library.reader_kind(%Book{library_id: books.id}, %BookFile{format: :epub}) == :text
      # The text reader can't open an archive of pictures.
      assert Library.reader_kind(%Book{library_id: books.id}, %BookFile{format: :cbz}) == :images
    end

    test "a comics library opens them as pages" do
      comics = library(:comics)
      assert Library.reader_kind(%Book{library_id: comics.id}, %BookFile{format: :pdf}) == :images
    end

    test "a detected kind still wins" do
      books = library(:books)
      assert Library.reader_kind(%Book{library_id: books.id}, %BookFile{format: :pdf, content_kind: :images}) == :images
    end
  end

  describe "Access.narrow/2" do
    setup do
      comics = library(:comics)
      books = library(:books)
      {:ok, c} = Library.create_book(%{library_id: comics.id, type: "standalone", title: "A Comic"})
      {:ok, b} = Library.create_book(%{library_id: books.id, type: "standalone", title: "A Novel"})
      %{comics: comics, books: books, comic: c, novel: b}
    end

    defp titles(access), do: access |> Access.books() |> Repo.all() |> Enum.map(& &1.title) |> Enum.sort()

    test "limits an admin's access to the given libraries", %{books: books} do
      assert titles(Access.all()) == ["A Comic", "A Novel"]

      narrowed = Access.narrow(Access.all(), [books.id])
      assert titles(narrowed) == ["A Novel"]
      assert Access.can_download?(narrowed, books.id)
    end

    test "never widens a user's access", %{comics: comics, books: books} do
      {:ok, user} = Accounts.create_user(%{email: "n@example.com", username: "narrow", password: "password1234"})
      {:ok, _} = Library.set_library_permission(%{user_id: user.id, library_id: comics.id, can_read: true})

      access = Access.for_user(user)
      assert titles(Access.narrow(access, [books.id])) == []
      assert titles(Access.narrow(access, [comics.id, books.id])) == ["A Comic"]
      refute Access.can_download?(Access.narrow(access, [comics.id]), comics.id)
    end
  end
end
