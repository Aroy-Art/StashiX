# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Calibre.PollerTest do
  use Stashix.DataCase, async: false

  alias Stashix.Calibre.Poller
  alias Stashix.CalibreFixtures
  alias Stashix.Library
  alias Stashix.Library.Book

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    # Short: book_covers.path is a varchar(255).
    thumbs = Path.join(System.tmp_dir!(), "stashix_test_thumbs_#{System.unique_integer([:positive])}")
    Application.put_env(:stashix, :thumbnail_dir, thumbs)

    on_exit(fn ->
      Application.delete_env(:stashix, :thumbnail_dir)
      File.rm_rf(thumbs)
    end)

    root = CalibreFixtures.make_library(Path.join(tmp, "Calibre"), [%{title: "Dune", authors: ["Frank Herbert"]}])
    {:ok, lib} = Library.create_library(%{name: "Calibre", root_path: root, kind: :books, source: :calibre})
    {:ok, _folders} = Library.create_library(%{name: "Comics", root_path: Path.join(tmp, "Comics")})
    %{root: root, lib: lib}
  end

  test "a library scan of a Calibre library syncs it", %{lib: lib} do
    Stashix.Scanner.scan_sync(lib.id)
    assert Repo.get_by!(Book, title: "Dune").calibre_id
  end

  test "stale until synced, again after Calibre writes", %{root: root, lib: lib} do
    assert Poller.stale_libraries() == [lib.id]

    Stashix.Scanner.scan_sync(lib.id)
    assert Poller.stale_libraries() == []

    CalibreFixtures.execute(root, "UPDATE books SET title = 'Dune Messiah'")
    assert Poller.stale_libraries() == [lib.id]
  end

  test "stale while files are missing", %{root: root, lib: lib} do
    [[path]] = CalibreFixtures.query(root, "SELECT path FROM books")
    File.rm_rf!(Path.join(root, path))

    Stashix.Scanner.scan_sync(lib.id)
    assert Poller.stale_libraries() == [lib.id]
  end

  test "a missing database is reported once", %{root: root, lib: lib} do
    File.rm!(Path.join(root, "metadata.db"))
    assert Poller.stale_libraries() == [lib.id]

    Stashix.Scanner.scan_sync(lib.id)
    assert Poller.stale_libraries() == []
  end
end
