# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Metadata.ImporterCreditsTest do
  use Stashix.DataCase, async: true

  import Ecto.Query
  import Stashix.MetadataFixtures

  alias Stashix.Library.BookCredit
  alias Stashix.Metadata.Importer
  alias Stashix.Repo

  setup do
    lib = library_fixture(System.tmp_dir!())
    %{book: book_fixture(lib, series_fixture(lib))}
  end

  defp roles(book) do
    from(c in BookCredit, where: c.book_id == ^book.id, join: p in assoc(c, :creator), select: {p.name, c.role})
    |> Repo.all()
    |> Enum.sort()
  end

  test "keeps a creator listed without a role as Other", %{book: book} do
    {:ok, _} =
      Importer.replace_book_metadata(book, %{
        credits: [%{creator: "Tony Takezaki", roles: []}, %{creator: "Tom King", roles: ["Writer"]}]
      })

    assert roles(book) == [{"Tom King", :Writer}, {"Tony Takezaki", :Other}]
  end

  test "a new book's rows are added without clearing first", %{book: book} do
    {:ok, _} = Importer.replace_book_metadata(book, %{credits: [%{creator: "Tom King", roles: ["Writer"]}]})

    # `new: true` promises there's nothing to clear, so the old row stays.
    {:ok, _} =
      Importer.replace_book_metadata(book, %{credits: [%{creator: "Mitch Gerads", roles: ["Artist"]}]}, new: true)

    assert roles(book) == [{"Mitch Gerads", :Artist}, {"Tom King", :Writer}]

    {:ok, _} = Importer.replace_book_metadata(book, %{credits: [%{creator: "Mitch Gerads", roles: ["Artist"]}]})
    assert roles(book) == [{"Mitch Gerads", :Artist}]
  end
end
