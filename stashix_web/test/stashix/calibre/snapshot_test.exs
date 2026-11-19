# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Calibre.SnapshotTest do
  use ExUnit.Case, async: true

  alias Stashix.Calibre.Snapshot
  alias Stashix.CalibreFixtures

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    root = CalibreFixtures.make_library(Path.join(tmp, "Calibre"), [%{title: "Dune", authors: ["Frank Herbert"]}])
    %{root: root, id: "lib-#{System.unique_integer([:positive])}"}
  end

  test "copies the database and reads the copy", %{root: root, id: id} do
    assert Snapshot.calibre_library?(root)
    assert {:ok, snap} = Snapshot.take(id, root)
    assert snap.path == Snapshot.path(id)
    assert Snapshot.stamp(root) == {:ok, snap.stamp}

    {:ok, conn} = Snapshot.open(snap)
    assert {:ok, [["Dune"]]} = Snapshot.rows(conn, "SELECT title FROM books")
    Exqlite.Sqlite3.close(conn)
    Snapshot.delete(id)
  end

  test "a commit changes the stamp, even in the same second", %{root: root} do
    {:ok, before} = Snapshot.stamp(root)
    CalibreFixtures.execute(root, "UPDATE books SET title = 'Dunf'")
    {:ok, later} = Snapshot.stamp(root)

    assert later.counter > before.counter
    refute later == before
  end

  test "a file replaced by rename (rsync) changes the stamp", %{root: root, tmp_dir: tmp} do
    {:ok, before} = Snapshot.stamp(root)
    copy = Path.join(tmp, ".metadata.db.XYZ")
    File.cp!(Snapshot.db_path(root), copy)
    File.rename!(copy, Snapshot.db_path(root))

    {:ok, later} = Snapshot.stamp(root)
    assert later.inode != before.inode
  end

  test "no metadata.db", %{tmp_dir: tmp, id: id} do
    refute Snapshot.calibre_library?(tmp)
    assert Snapshot.take(id, tmp) == {:error, :no_database}
  end

  test "busy while a journal exists", %{root: root, id: id} do
    File.write!(Snapshot.db_path(root) <> "-journal", "")
    assert Snapshot.stamp(root) == {:error, :busy}
    assert Snapshot.take(id, root, retry_ms: 0) == {:error, :busy}
    refute File.exists?(Snapshot.path(id))
  end

  test "retries when the file changes while it's copied", %{root: root, id: id} do
    attempts = :counters.new(1, [])

    copy = fn source, target ->
      :counters.add(attempts, 1, 1)
      result = File.copy(source, target)
      # Calibre commits during the first copy only.
      if :counters.get(attempts, 1) == 1, do: CalibreFixtures.execute(root, "UPDATE books SET title = 'Dune Messiah'")
      result
    end

    assert {:ok, snap} = Snapshot.take(id, root, retry_ms: 0, copy: copy)
    assert :counters.get(attempts, 1) == 2

    {:ok, conn} = Snapshot.open(snap)
    assert {:ok, [["Dune Messiah"]]} = Snapshot.rows(conn, "SELECT title FROM books")
    Exqlite.Sqlite3.close(conn)
  end

  test "gives up when the file keeps changing", %{root: root, id: id} do
    copy = fn source, target ->
      result = File.copy(source, target)
      CalibreFixtures.execute(root, "UPDATE books SET title = title || '!'")
      result
    end

    assert Snapshot.take(id, root, retry_ms: 0, copy: copy) == {:error, :busy}
  end

  test "not a SQLite file", %{root: root, id: id} do
    File.write!(Snapshot.db_path(root), "not a database at all, just some text here")
    assert Snapshot.take(id, root) == {:error, :corrupt}
  end

  test "names what an unknown schema lacks", %{root: root, id: id} do
    CalibreFixtures.execute(root, "DROP TRIGGER books_delete_trg")
    CalibreFixtures.execute(root, "DROP TABLE identifiers")
    CalibreFixtures.execute(root, "ALTER TABLE books DROP COLUMN uuid")

    assert Snapshot.take(id, root) == {:error, {:unsupported, ["books.uuid", "identifiers"]}}
  end
end
