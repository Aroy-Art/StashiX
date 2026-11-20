# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Calibre.SyncTest do
  use Stashix.DataCase, async: false

  alias Stashix.Calibre.Sync
  alias Stashix.CalibreFixtures
  alias Stashix.Library
  alias Stashix.Library.{Book, BookCover, BookFile, Creator, Series}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    # Short: book_covers.path is a varchar(255).
    thumbs = Path.join(System.tmp_dir!(), "stashix_test_thumbs_#{System.unique_integer([:positive])}")
    Application.put_env(:stashix, :thumbnail_dir, thumbs)

    on_exit(fn ->
      Application.delete_env(:stashix, :thumbnail_dir)
      File.rm_rf(thumbs)
    end)

    root = CalibreFixtures.make_library(Path.join(tmp, "Calibre"))
    {:ok, lib} = Library.create_library(%{name: "Calibre", root_path: root, kind: :books, source: :calibre})
    %{root: root, lib: lib}
  end

  defp sync!(lib, opts \\ []) do
    {:ok, summary} = Sync.run(Repo.get!(Library.Library, lib.id), opts)
    summary
  end

  defp book(calibre_id) do
    Repo.one!(from b in Book, where: b.calibre_id == ^calibre_id)
    |> Repo.preload([
      :series,
      :tags,
      :publishers,
      :external_ids,
      :urls,
      :cover,
      files: from(f in BookFile, order_by: f.path),
      credits: :creator
    ])
  end

  defp omens do
    %{
      title: "Good Omens",
      sort: "Good Omens",
      uuid: "11111111-0000-0000-0000-000000000001",
      authors: ["Terry Pratchett", "Neil Gaiman"],
      series: {"Omens", 1},
      publisher: "Gollancz",
      tags: ["Fantasy", "Comedy"],
      languages: ["eng"],
      rating: 8,
      comments: "<p>The world ends on <b>Saturday</b>.</p>",
      identifiers: %{"isbn" => "9780575048003", "google" => "g1"},
      pubdate: "1990-05-01 00:00:00+00:00",
      formats: ["EPUB", "PDF"]
    }
  end

  test "first sync adds books with Calibre's metadata", %{root: root, lib: lib} do
    id = CalibreFixtures.add_book(root, omens())
    CalibreFixtures.add_book(root, %{title: "Alone", authors: ["Solo Writer"]})

    summary = sync!(lib)
    assert %{books: 2, added: 2, updated: 0, unchanged: 0, removed: 0, missing_files: 0} = summary

    b = book(id)
    assert b.title == "Good Omens"
    assert b.calibre_uuid == "11111111-0000-0000-0000-000000000001"
    assert b.series.name == "Omens"
    assert b.series.calibre_id
    assert Decimal.equal?(b.issue_number, 1)
    assert b.type == "issue"
    assert b.summary == "The world ends on Saturday."
    assert {b.year, b.language, b.rating, b.isbn} == {1990, "en", 4.0, "9780575048003"}
    assert Enum.map(b.publishers, & &1.name) == ["Gollancz"]
    assert b.tags |> Enum.map(& &1.name) |> Enum.sort() == ["Comedy", "Fantasy"]
    assert Enum.map(b.external_ids, &{&1.source, &1.source_id}) == [{:"Google Books", "g1"}]

    assert b.credits |> Enum.map(&{&1.creator.name, &1.role}) |> Enum.sort() ==
             [{"Neil Gaiman", :Writer}, {"Terry Pratchett", :Writer}]

    assert Repo.get_by!(Creator, name: "Terry Pratchett").sort_name == "Pratchett, Terry"
    assert is_nil(b.deleted_at)
    assert [%{format: :epub, deleted_at: nil}, %{format: :pdf, deleted_at: nil}] = b.files
    assert Enum.all?(b.files, &String.starts_with?(&1.path, root))
    assert %BookCover{} = b.cover

    alone = Repo.get_by!(Book, title: "Alone")
    assert {alone.type, alone.series_id} == {"standalone", nil}

    state = Repo.get!(Library.Library, lib.id).calibre_state
    assert state["error"] == nil
    assert state["summary"]["added"] == 2
  end

  test "an unchanged library writes nothing; a renamed tag rewrites its books", %{root: root, lib: lib} do
    id = CalibreFixtures.add_book(root, omens())
    sync!(lib)
    before = book(id)

    assert %{unchanged: 1, added: 0, updated: 0} = sync!(lib)
    assert book(id).updated_at == before.updated_at

    # Renaming a tag in Calibre doesn't touch books.last_modified.
    CalibreFixtures.execute(root, "UPDATE tags SET name = 'Humour' WHERE name = 'Comedy'")
    assert %{updated: 1} = sync!(lib)
    assert book(id).tags |> Enum.map(& &1.name) |> Enum.sort() == ["Fantasy", "Humour"]
  end

  test "Calibre wins over locks; Stashix-only fields stay", %{root: root, lib: lib} do
    id = CalibreFixtures.add_book(root, omens())
    sync!(lib)

    {:ok, _} = Library.update_book(book(id), %{title: "Mine", age_rating: :mature, locked_fields: ["title"]})
    CalibreFixtures.execute(root, "UPDATE books SET title = 'Good Omens (Revised)'")
    sync!(lib)

    b = book(id)
    assert b.title == "Good Omens (Revised)"
    assert b.age_rating == :mature
  end

  test "books removed from Calibre are soft-deleted, with their empty series", %{root: root, lib: lib} do
    id = CalibreFixtures.add_book(root, omens())
    sync!(lib)
    series_id = book(id).series_id

    CalibreFixtures.execute(root, "DELETE FROM books WHERE id = ?", [id])
    assert %{removed: 1, books: 0} = sync!(lib)

    b = Repo.get_by!(Book, calibre_uuid: "11111111-0000-0000-0000-000000000001")
    assert b.deleted_at
    assert is_nil(b.calibre_id)
    assert Repo.get!(Series, series_id).deleted_at

    # Restored in Calibre (same uuid, new id): the same book comes back.
    new_id = CalibreFixtures.add_book(root, omens())
    assert %{added: 0, updated: 1} = sync!(lib)
    assert book(new_id).id == b.id
    assert is_nil(book(new_id).deleted_at)
  end

  test "a file not on disk yet is missing, and found later", %{root: root, lib: lib} do
    id = CalibreFixtures.add_book(root, omens())
    [[path]] = CalibreFixtures.query(root, "SELECT path FROM books")
    pdf = Path.join([root, path, "Good Omens - Terry Pratchett.pdf"])
    epub = Path.join([root, path, "Good Omens - Terry Pratchett.epub"])
    File.rename!(pdf, pdf <> ".away")

    assert %{missing_files: 1} = sync!(lib)
    assert [%{format: :epub, deleted_at: nil}, %{format: :pdf, deleted_at: %NaiveDateTime{}}] = book(id).files
    assert is_nil(book(id).deleted_at)

    # With no file on disk at all the book hides…
    File.rename!(epub, epub <> ".away")
    assert %{missing_files: 2} = sync!(lib)
    assert book(id).deleted_at

    # …and comes back when rsync delivers them.
    File.rename!(pdf <> ".away", pdf)
    File.rename!(epub <> ".away", epub)
    assert %{missing_files: 0} = sync!(lib)
    b = book(id)
    assert is_nil(b.deleted_at)
    assert Enum.all?(b.files, &is_nil(&1.deleted_at))
  end

  test "a format removed in Calibre loses its file row", %{root: root, lib: lib} do
    id = CalibreFixtures.add_book(root, omens())
    sync!(lib)

    CalibreFixtures.execute(root, "DELETE FROM data WHERE format = 'PDF'")
    sync!(lib)
    assert [%{format: :epub}] = book(id).files
  end

  test "a rebuilt Calibre database (new ids, same uuids) keeps the books", %{root: root, lib: lib} do
    a = CalibreFixtures.add_book(root, %{title: "A", uuid: "aaaaaaaa-0000-0000-0000-000000000000", series: {"S", 1}})
    b = CalibreFixtures.add_book(root, %{title: "B", uuid: "bbbbbbbb-0000-0000-0000-000000000000", series: {"S", 2}})
    sync!(lib)
    ids = %{a: book(a).id, b: book(b).id}
    series_id = book(a).series_id

    # Same books, ids swapped.
    File.rm!(Path.join(root, "metadata.db"))
    CalibreFixtures.make_library(root)
    CalibreFixtures.add_book(root, %{id: b, title: "A", uuid: "aaaaaaaa-0000-0000-0000-000000000000", series: {"S", 1}})
    CalibreFixtures.add_book(root, %{id: a, title: "B", uuid: "bbbbbbbb-0000-0000-0000-000000000000", series: {"S", 2}})

    assert %{added: 0, removed: 0} = sync!(lib)
    assert book(b).id == ids.a
    assert book(a).id == ids.b
    assert book(a).series_id == series_id
  end

  test "books sharing new authors and publishers all import", %{root: root, lib: lib} do
    for n <- 1..12,
        do:
          CalibreFixtures.add_book(root, %{title: "Part #{n}", authors: ["Ann Author", "Bo Writer"], publisher: "Press"})

    assert %{added: 12, failed: 0} = sync!(lib)
    assert Repo.aggregate(from(c in Creator, where: c.name in ["Ann Author", "Bo Writer"]), :count) == 2
  end

  test "custom columns of every kind", %{root: root, lib: lib} do
    id = CalibreFixtures.add_book(root, omens())

    cols =
      for {label, name, type, opts} <- [
            {"read", "Read", "bool", []},
            {"progress", "Progress", "int", []},
            {"score", "Score", "float", []},
            {"finished", "Finished", "datetime", []},
            {"review", "Review", "comments", []},
            {"shelf", "Shelf", "enumeration", []},
            {"moods", "Moods", "text", [multiple: true]},
            {"location", "Location", "text", []},
            {"universe", "Universe", "series", []},
            {"stars", "My stars", "rating", []},
            {"empty", "Never set", "text", []}
          ],
          into: %{},
          do: {label, CalibreFixtures.add_custom_column(root, label, name, type, opts)}

    for {label, value} <- [
          {"read", 1},
          {"progress", 42},
          {"score", 7.5},
          {"finished", "2024-03-05 10:00:00+00:00"},
          {"review", "<p>Loved <b>it</b>.</p>"},
          {"shelf", "Favourites"},
          {"moods", ["funny", "dark"]},
          {"location", "Box 3"},
          {"universe", {"Discworld-ish", 2.5}},
          {"stars", 8}
        ],
        do: CalibreFixtures.set_custom(root, cols[label], id, value)

    sync!(lib)

    assert book(id).calibre_fields == %{
             "read" => %{"name" => "Read", "type" => "bool", "value" => true},
             "progress" => %{"name" => "Progress", "type" => "int", "value" => 42},
             "score" => %{"name" => "Score", "type" => "float", "value" => 7.5},
             "finished" => %{"name" => "Finished", "type" => "datetime", "value" => "2024-03-05"},
             "review" => %{"name" => "Review", "type" => "comments", "value" => "Loved it."},
             "shelf" => %{"name" => "Shelf", "type" => "enumeration", "value" => "Favourites"},
             "moods" => %{"name" => "Moods", "type" => "text", "value" => ["funny", "dark"]},
             "location" => %{"name" => "Location", "type" => "text", "value" => "Box 3"},
             "universe" => %{
               "name" => "Universe",
               "type" => "series",
               "value" => %{"name" => "Discworld-ish", "index" => 2.5}
             },
             "stars" => %{"name" => "My stars", "type" => "rating", "value" => 4.0}
           }

    columns = Repo.get!(Library.Library, lib.id).calibre_state["columns"]
    assert %{"label" => "moods", "name" => "Moods", "type" => "text", "multiple" => true} in columns
    assert length(columns) == 11

    # A changed value rewrites the book.
    CalibreFixtures.set_custom(root, cols["read"], id, 0)
    assert %{updated: 1} = sync!(lib)
    assert book(id).calibre_fields["read"]["value"] == false
  end

  describe "read status from a custom column" do
    setup %{root: root, lib: lib} do
      {:ok, user} =
        Stashix.Accounts.create_user(%{email: "r@example.com", username: "calreader", password: "password1234"})

      id = CalibreFixtures.add_book(root, omens())
      read = CalibreFixtures.add_custom_column(root, "read", "Read", "bool")
      pct = CalibreFixtures.add_custom_column(root, "pct", "Percent", "int")
      %{user: user, id: id, read: read, pct: pct, lib: lib}
    end

    defp progression(user, calibre_id) do
      case Library.get_progress(user.id, book(calibre_id).id) do
        nil -> nil
        p -> p.progression
      end
    end

    defp set_read(lib, user, column) do
      {:ok, lib} =
        Library.update_library(lib, %{calibre_settings: %{"read_user_id" => user.id, "read_column" => column}})

      lib
    end

    test "a yes marks the book read, and a later no doesn't unread it", %{root: root, lib: lib, user: user} = c do
      lib = set_read(lib, user, "read")
      CalibreFixtures.set_custom(root, c.read, c.id, 1)

      assert %{read_marked: 1} = sync!(lib)
      assert progression(user, c.id) == 1.0

      CalibreFixtures.set_custom(root, c.read, c.id, 0)
      assert %{read_marked: 0} = sync!(lib)
      assert progression(user, c.id) == 1.0
    end

    test "a percent column moves progress up only", %{root: root, lib: lib, user: user} = c do
      lib = set_read(lib, user, "pct")
      CalibreFixtures.set_custom(root, c.pct, c.id, 40)
      sync!(lib)
      assert progression(user, c.id) == 0.4

      CalibreFixtures.set_custom(root, c.pct, c.id, 20)
      sync!(lib)
      assert progression(user, c.id) == 0.4

      CalibreFixtures.set_custom(root, c.pct, c.id, 75)
      sync!(lib)
      assert progression(user, c.id) == 0.75
    end

    test "only values that changed in Calibre are applied", %{root: root, lib: lib, user: user} = c do
      lib = set_read(lib, user, "pct")
      CalibreFixtures.set_custom(root, c.pct, c.id, 40)
      sync!(lib)

      # Read further in Stashix, then sync again with Calibre unchanged.
      Library.update_progress(Library.Access.all(), user.id, book(c.id).id, 0, progression: 0.9)
      assert %{read_marked: 0} = sync!(lib)
      assert progression(user, c.id) == 0.9
    end

    test "choosing the column later applies the values already there", %{root: root, lib: lib, user: user} = c do
      CalibreFixtures.set_custom(root, c.read, c.id, 1)
      sync!(lib)
      assert progression(user, c.id) == nil

      lib = set_read(lib, user, "read")
      assert %{read_marked: 1} = sync!(lib)
      assert progression(user, c.id) == 1.0
    end
  end

  test "a forced sync rewrites every book", %{root: root, lib: lib} do
    CalibreFixtures.add_book(root, omens())
    sync!(lib)
    assert %{updated: 1, unchanged: 0} = sync!(lib, force: true)
  end

  test "reports formats Stashix can't read", %{root: root, lib: lib} do
    CalibreFixtures.add_book(root, %{title: "Txt", formats: ["EPUB", "TXT"]})
    assert %{skipped_formats: %{"TXT" => 1}} = sync!(lib)
  end

  test "an unreadable library is an error in the library's state", %{root: root, lib: lib} do
    File.rm!(Path.join(root, "metadata.db"))
    assert {:error, :no_database} = Sync.run(lib)
    assert Repo.get!(Library.Library, lib.id).calibre_state["error"] == "No metadata.db in the library folder"
  end

  test "preferred_file/1 opens EPUB before PDF" do
    files = [%{format: :pdf}, %{format: :cbz}, %{format: :epub}]
    assert Sync.preferred_file(files).format == :epub
    assert Sync.preferred_file([]) == nil
  end
end
