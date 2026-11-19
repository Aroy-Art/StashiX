# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Calibre.GuardRailsTest do
  use Stashix.DataCase, async: false

  alias Stashix.{Calibre, Library}
  alias Stashix.CalibreFixtures
  alias Stashix.Library.Book
  alias Stashix.Metadata.Workers.{MatchBookWorker, MatchLibraryWorker, MatchSeriesWorker}
  alias Stashix.Metadata.Writer.FileWriter

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    # Short: book_covers.path is a varchar(255).
    thumbs = Path.join(System.tmp_dir!(), "stashix_test_thumbs_#{System.unique_integer([:positive])}")
    Application.put_env(:stashix, :thumbnail_dir, thumbs)

    on_exit(fn ->
      Application.delete_env(:stashix, :thumbnail_dir)
      File.rm_rf(thumbs)
    end)

    root =
      CalibreFixtures.make_library(Path.join(tmp, "Calibre"), [
        %{title: "Dune", authors: ["Frank Herbert"], series: {"Dune", 1}}
      ])

    {:ok, lib} = Library.create_library(%{name: "Calibre", root_path: root, kind: :books, source: :calibre})
    {:ok, _} = Stashix.Calibre.Sync.run(lib)
    %{root: root, lib: lib, book: Repo.get_by!(Book, title: "Dune")}
  end

  test "library?/1", %{lib: lib, book: book, tmp_dir: tmp} do
    {:ok, comics} = Library.create_library(%{name: "Comics", root_path: Path.join(tmp, "Comics")})

    assert Calibre.library?(lib)
    assert Calibre.library?(lib.id)
    assert Calibre.library?(book)
    refute Calibre.library?(comics.id)
    refute Calibre.library?(nil)
  end

  describe "libraries can't overlap a Calibre library" do
    test "a folder library inside it, or around it", %{root: root, tmp_dir: tmp} do
      assert {:error, cs} = Library.create_library(%{name: "Inner", root_path: Path.join(root, "Frank Herbert")})
      assert {"overlaps the library %{name}", [name: "Calibre"]} = cs.errors[:root_path]

      assert {:error, _} = Library.create_library(%{name: "Outer", root_path: tmp <> "/"})
    end

    test "a Calibre library around a folder library", %{tmp_dir: tmp} do
      {:ok, _} = Library.create_library(%{name: "Comics", root_path: Path.join(tmp, "Other/Comics")})

      assert {:error, _} =
               Library.create_library(%{name: "Cal 2", root_path: Path.join(tmp, "Other"), source: :calibre})
    end

    test "side by side is fine, and a library may keep its own path", %{lib: lib, tmp_dir: tmp} do
      assert {:ok, _} = Library.create_library(%{name: "Comics", root_path: Path.join(tmp, "Comics")})
      assert {:ok, _} = Library.create_library(%{name: "Calib", root_path: Path.join(tmp, "CalibreX")})
      assert {:ok, _} = Library.update_library(lib, %{name: "Renamed"})
    end
  end

  test "metadata is never written into a Calibre library's files", %{book: book} do
    [file] = Library.get_book_files(book.id)
    before = File.stat!(file.path)
    dir = File.ls!(Path.dirname(file.path))

    assert FileWriter.write_book(book, %{"write_to_files" => true, "write_comicinfo" => true}) == :ok
    assert File.stat!(file.path) == before
    assert File.ls!(Path.dirname(file.path)) == dir
  end

  test "matching jobs are cancelled", %{lib: lib, book: book} do
    assert {:cancel, :calibre_library} = MatchBookWorker.perform(%Oban.Job{args: %{"book_id" => book.id}})
    assert {:cancel, :calibre_library} = MatchSeriesWorker.perform(%Oban.Job{args: %{"series_id" => book.series_id}})
    assert {:cancel, :calibre_library} = MatchLibraryWorker.perform(%Oban.Job{args: %{"library_id" => lib.id}})
  end
end
