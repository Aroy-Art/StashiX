# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.ScannerTest do
  use Stashix.DataCase, async: false

  alias Stashix.{Library, Scanner, Repo}
  alias Stashix.Library.{Access, Book, BookCover}

  setup do
    tmp = Path.join(System.tmp_dir!(), "stashix_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, lib} = Library.create_library(%{name: "Test Library", root_path: tmp})
    %{lib: lib, tmp: tmp}
  end

  # ── parse_folder_name ──────────────────────────────────────────────────────

  describe "parse_folder_name/1" do
    test "plain name has no years" do
      assert Scanner.parse_folder_name("My Series") == {"My Series", nil, nil, false}
    end

    test "single year → start_year only, not ongoing" do
      assert Scanner.parse_folder_name("AD Police (1994)") == {"AD Police", 1994, nil, false}
    end

    test "year range → start and end year, not ongoing" do
      assert Scanner.parse_folder_name("Battle Angel Alita (1994-1998)") ==
               {"Battle Angel Alita", 1994, 1998, false}
    end

    test "trailing dash → ongoing" do
      assert Scanner.parse_folder_name("The Disavowed (2025-)") ==
               {"The Disavowed", 2025, nil, true}
    end

    test "strips whitespace around name" do
      assert Scanner.parse_folder_name("  Batman  (1940)") == {"Batman", 1940, nil, false}
    end

    test "name with no year and trailing dash treated as plain" do
      assert Scanner.parse_folder_name("No Year") == {"No Year", nil, nil, false}
    end
  end

  # ── find_sidecar_image ────────────────────────────────────────────────────

  describe "find_sidecar_image/1" do
    test "returns nil when no sidecar exists", %{tmp: tmp} do
      cbz = Path.join(tmp, "book.cbz")
      File.write!(cbz, "fake")
      assert Scanner.find_sidecar_image(cbz) == nil
    end

    test "finds .jpg sidecar", %{tmp: tmp} do
      cbz = Path.join(tmp, "book.cbz")
      jpg = Path.join(tmp, "book.jpg")
      File.write!(cbz, "fake")
      File.write!(jpg, "image")
      assert Scanner.find_sidecar_image(cbz) == jpg
    end

    test "finds .png sidecar when no jpg", %{tmp: tmp} do
      cbz = Path.join(tmp, "book.cbz")
      png = Path.join(tmp, "book.png")
      File.write!(cbz, "fake")
      File.write!(png, "png")
      assert Scanner.find_sidecar_image(cbz) == png
    end

    test "prefers .jpg over .png when both exist", %{tmp: tmp} do
      cbz = Path.join(tmp, "book.cbz")
      jpg = Path.join(tmp, "book.jpg")
      png = Path.join(tmp, "book.png")
      File.write!(cbz, "fake")
      File.write!(jpg, "jpg")
      File.write!(png, "png")
      assert Scanner.find_sidecar_image(cbz) == jpg
    end
  end

  # ── standalone detection ──────────────────────────────────────────────────

  describe "scan_sync/2 standalone detection" do
    test "file at library root → standalone", %{lib: lib, tmp: tmp} do
      write_cbz(tmp, "My Book.cbz")
      Scanner.scan_sync(lib.id)
      assert [book] = Library.list_books(lib.id, access: Access.all())
      assert book.type == "standalone"
      assert book.series_id == nil
    end

    test "file in One-Shot folder → standalone", %{lib: lib, tmp: tmp} do
      write_cbz(mkdir(tmp, "One-Shot"), "Creepshow (1982).cbz")
      Scanner.scan_sync(lib.id)
      assert [book] = Library.list_books(lib.id, access: Access.all())
      assert book.type == "standalone"
      assert book.series_id == nil
    end

    test "standalone detection is case-insensitive (one shot)", %{lib: lib, tmp: tmp} do
      write_cbz(mkdir(tmp, "one shot"), "Some Book.cbz")
      Scanner.scan_sync(lib.id)
      assert [book] = Library.list_books(lib.id, access: Access.all())
      assert book.type == "standalone"
    end

    test "standalone detection is case-insensitive (ONESHOT)", %{lib: lib, tmp: tmp} do
      write_cbz(mkdir(tmp, "ONESHOT"), "Some Book.cbz")
      Scanner.scan_sync(lib.id)
      assert [book] = Library.list_books(lib.id, access: Access.all())
      assert book.type == "standalone"
    end

    test "configured standalone folder → standalone", %{lib: lib, tmp: tmp} do
      {:ok, lib} = Library.update_library(lib, %{standalone_folders: ["Specials"]})
      write_cbz(mkdir(tmp, "Specials"), "Annual.cbz")
      Scanner.scan_sync(lib.id)
      assert [book] = Library.list_books(lib.id, access: Access.all())
      assert book.type == "standalone"
    end

    test "configured standalone folder is case-insensitive", %{lib: lib, tmp: tmp} do
      {:ok, lib} = Library.update_library(lib, %{standalone_folders: ["Specials"]})
      write_cbz(mkdir(tmp, "SPECIALS"), "Annual.cbz")
      Scanner.scan_sync(lib.id)
      assert [book] = Library.list_books(lib.id, access: Access.all())
      assert book.type == "standalone"
    end

    test "unknown folder → issue, not standalone", %{lib: lib, tmp: tmp} do
      write_cbz(mkdir(tmp, "Regular Series"), "Issue 001.cbz")
      Scanner.scan_sync(lib.id)
      assert [book] = Library.list_books(lib.id, access: Access.all())
      assert book.type == "issue"
    end
  end

  # ── series creation ───────────────────────────────────────────────────────

  describe "scan_sync/2 series creation" do
    test "series name stripped of year range", %{lib: lib, tmp: tmp} do
      write_cbz(mkdir(tmp, "Batman (1940-2011)"), "Batman 001.cbz")
      Scanner.scan_sync(lib.id)
      assert [book] = Library.list_books(lib.id, access: Access.all())
      series = Library.get_series!(book.series_id)
      assert series.name == "Batman"
      assert series.start_year == 1940
      assert series.end_year == 2011
      assert series.ongoing == false
    end

    test "ongoing series folder sets ongoing=true", %{lib: lib, tmp: tmp} do
      write_cbz(mkdir(tmp, "The Disavowed (2025-)"), "Issue 001.cbz")
      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())
      series = Library.get_series!(book.series_id)
      assert series.name == "The Disavowed"
      assert series.start_year == 2025
      assert series.end_year == nil
      assert series.ongoing == true
    end

    test "single-year folder → completed series", %{lib: lib, tmp: tmp} do
      write_cbz(mkdir(tmp, "Big Ducks (1984)"), "Issue 001.cbz")
      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())
      series = Library.get_series!(book.series_id)
      assert series.name == "Big Ducks"
      assert series.start_year == 1984
      assert series.ongoing == false
    end

    test "plain folder name → series with no years", %{lib: lib, tmp: tmp} do
      write_cbz(mkdir(tmp, "Akira"), "Akira v1.cbz")
      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())
      series = Library.get_series!(book.series_id)
      assert series.name == "Akira"
      assert series.start_year == nil
      assert series.end_year == nil
    end

    test "multiple files in same folder → grouped into one series", %{lib: lib, tmp: tmp} do
      folder = mkdir(tmp, "X-Men (1963-2011)")
      write_cbz(folder, "Issue 001.cbz")
      write_cbz(folder, "Issue 002.cbz")
      write_cbz(folder, "Issue 003.cbz")
      Scanner.scan_sync(lib.id)
      books = Library.list_books(lib.id, access: Access.all())
      assert length(books) == 3
      series_ids = books |> Enum.map(& &1.series_id) |> Enum.uniq()
      assert [series_id] = series_ids
      assert series_id != nil
    end

    test "two different series folders → two separate series", %{lib: lib, tmp: tmp} do
      write_cbz(mkdir(tmp, "Batman (1940-2011)"), "Batman 001.cbz")
      write_cbz(mkdir(tmp, "Superman (1939-)"), "Superman 001.cbz")
      Scanner.scan_sync(lib.id)
      books = Library.list_books(lib.id, access: Access.all())
      series_ids = books |> Enum.map(& &1.series_id) |> Enum.uniq()
      assert length(series_ids) == 2
    end
  end

  # ── issue number parsing ──────────────────────────────────────────────────

  describe "scan_sync/2 issue number parsing" do
    test "Series (YEAR) - Issue N filename sets issue_number", %{lib: lib, tmp: tmp} do
      folder = mkdir(tmp, "Bubblegum Crisis: Grand Mal (1994)")
      write_cbz(folder, "Bubblegum Crisis: Grand Mal (1994) - Issue 3.cbz")
      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())
      assert book.issue_number == Decimal.new("3")
    end

    test "Series (YEAR) - Issue N sets correct series", %{lib: lib, tmp: tmp} do
      folder = mkdir(tmp, "Saga (2012)")
      write_cbz(folder, "Saga (2012) - Issue 1.cbz")
      write_cbz(folder, "Saga (2012) - Issue 2.cbz")
      Scanner.scan_sync(lib.id)
      books = Library.list_books(lib.id, sort: "issue_asc", access: Access.all())
      assert length(books) == 2
      [b1, b2] = books
      assert b1.issue_number == Decimal.new("1")
      assert b2.issue_number == Decimal.new("2")
      assert b1.series_id == b2.series_id
    end

    test "Series NN - Title (Publisher YEAR) filename parses all fields", %{lib: lib, tmp: tmp} do
      folder = mkdir(tmp, "The Bank (2025)")

      write_cbz(
        folder,
        "The Bank 01 - The Waterloo Insider (Cinebook 2025) (webrip) (MagicMan-DCP).cbz"
      )

      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())
      assert book.issue_number == Decimal.new("1")
      assert book.title == "The Waterloo Insider"
      assert book.year == 2025
      assert book.source_format == "webrip"
    end

    test "Issue N - Title filename sets issue_number", %{lib: lib, tmp: tmp} do
      folder = mkdir(tmp, "Battle Angel Alita (1994)")
      write_cbz(folder, "Issue 1 - Rusty Angel.cbz")
      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())
      assert book.issue_number == Decimal.new("1")
      assert book.title == "Rusty Angel"
    end
  end

  # ── page count ────────────────────────────────────────────────────────────

  describe "scan_sync/2 page count" do
    test "counts pages from archive when no ComicInfo.xml", %{lib: lib, tmp: tmp} do
      write_cbz(tmp, "My Book.cbz", page_count: 5)
      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())
      assert book.page_count == 5
    end

    test "single-page archive counted correctly", %{lib: lib, tmp: tmp} do
      write_cbz(tmp, "My Book.cbz", page_count: 1)
      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())
      assert book.page_count == 1
    end

    test "archive count wins over ComicInfo PageCount and skips credit pages", %{lib: lib, tmp: tmp} do
      write_cbz(tmp, "My Book.cbz",
        page_count: 3,
        extra: [
          {~c"zGroup-Credit.jpg", "credit"},
          {~c"ComicInfo.xml", "<ComicInfo><Title>My Book</Title><PageCount>4</PageCount></ComicInfo>"}
        ]
      )

      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())
      assert book.page_count == 3
    end
  end

  # ── sidecar covers ────────────────────────────────────────────────────────

  describe "scan_sync/2 sidecar cover" do
    test "sidecar image creates cover record", %{lib: lib, tmp: tmp} do
      folder = mkdir(tmp, "My Series (2020)")
      write_cbz(folder, "Issue 001.cbz")
      File.write!(Path.join(folder, "Issue 001.jpg"), "fake jpeg")
      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())
      cover = Repo.get_by(BookCover, book_id: book.id)
      assert cover != nil
    end
  end

  # ── orphan handling ───────────────────────────────────────────────────────

  describe "scan_sync/2 orphan handling" do
    test "missing file soft-deleted on rescan", %{lib: lib, tmp: tmp} do
      cbz = write_cbz(tmp, "My Book.cbz")
      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())
      assert book.deleted_at == nil

      File.rm!(cbz)
      Scanner.scan_sync(lib.id)
      deleted = Repo.get!(Book, book.id)
      assert deleted.deleted_at != nil
    end

    test "restored file reappears after rescan", %{lib: lib, tmp: tmp} do
      cbz = write_cbz(tmp, "My Book.cbz")
      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())
      book_id = book.id

      File.rm!(cbz)
      Scanner.scan_sync(lib.id)
      assert Repo.get!(Book, book_id).deleted_at != nil

      write_cbz(tmp, "My Book.cbz")
      Scanner.scan_sync(lib.id)
      assert Repo.get!(Book, book_id).deleted_at == nil
    end
  end

  # ── force rescan ──────────────────────────────────────────────────────────

  describe "scan_sync/2 rename detection" do
    test "renamed file updates title and path, keeps same book record", %{lib: lib, tmp: tmp} do
      folder = mkdir(tmp, "Battle Angel Alita (1994-1998)")
      old_cbz = write_cbz(folder, "Volume 1 - Rusty Angel.cbz")
      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())
      assert book.title == "Rusty Angel"
      assert book.issue_number == Decimal.new("1")
      book_id = book.id

      new_cbz = Path.join(folder, "Issue 1 - Rusty Angel (1994).cbz")
      File.cp!(old_cbz, new_cbz)
      File.rm!(old_cbz)
      Scanner.scan_sync(lib.id)

      books = Library.list_books(lib.id, access: Access.all())
      assert length(books) == 1
      updated = hd(books)
      assert updated.id == book_id
      assert updated.title == "Rusty Angel"
      assert updated.issue_number == Decimal.new("1")
      assert updated.year == 1994
    end
  end

  describe "series folder rename" do
    alias Stashix.Library.{Series, SeriesExternalId}

    setup %{lib: lib, tmp: tmp} do
      old_dir = mkdir(tmp, "Barbarian (2026-)")
      for n <- 1..3, do: write_cbz(old_dir, "Barbarian #{String.pad_leading("#{n}", 3, "0")}.cbz")
      Scanner.scan_sync(lib.id)
      [series] = Repo.all(Series)
      new_dir = Path.join(tmp, "Barbarian (2026)")
      %{series: series, old_dir: old_dir, new_dir: new_dir}
    end

    defp live_series, do: Repo.all(from s in Series, where: is_nil(s.deleted_at))

    test "file-by-file rescan moves the series instead of creating one", ctx do
      File.rename!(ctx.old_dir, ctx.new_dir)
      for f <- File.ls!(ctx.new_dir), do: Scanner.scan_file_sync(ctx.lib.id, Path.join(ctx.new_dir, f))

      assert [series] = live_series()
      assert series.id == ctx.series.id
      assert series.path == ctx.new_dir
      assert series.ongoing == false
      assert length(Library.list_books(ctx.lib.id, access: Access.all())) == 3
    end

    test "a duplicate made for the renamed folder is merged back", ctx do
      File.rename!(ctx.old_dir, ctx.new_dir)
      [first | rest] = File.ls!(ctx.new_dir) |> Enum.sort()

      # What an older scanner left behind: a new series holding the issues it saw first.
      {:ok, dup} = Library.create_or_find_series(%{library_id: ctx.lib.id, name: "Barbarian", path: ctx.new_dir})
      Repo.update_all(from(s in Series, where: s.id == ^dup.id), set: [inserted_at: ~N[2099-01-01 00:00:00]])
      Repo.insert!(%SeriesExternalId{series_id: ctx.series.id, source: :Metron, source_id: "42"})

      for f <- rest do
        path = Path.join(ctx.new_dir, f)
        bf = Library.get_book_file_by_hash(Scanner.compute_hash(path, File.stat!(path).size))
        Library.update_book_file(bf, %{path: path})
        Repo.update_all(from(b in Book, where: b.id == ^bf.book_id), set: [series_id: dup.id])
      end

      Scanner.scan_file_sync(ctx.lib.id, Path.join(ctx.new_dir, first))

      assert [series] = live_series()
      assert series.id == ctx.series.id
      assert series.path == ctx.new_dir
      assert Repo.get(Series, dup.id) == nil
      assert [%{source_id: "42"}] = Repo.all(SeriesExternalId)
      assert Enum.all?(Library.list_books(ctx.lib.id, access: Access.all()), &(&1.series_id == series.id))
    end

    test "an edited series in the new folder is not merged", ctx do
      File.rename!(ctx.old_dir, ctx.new_dir)
      {:ok, other} = Library.create_or_find_series(%{library_id: ctx.lib.id, name: "Barbarian", path: ctx.new_dir})

      Repo.update_all(from(s in Series, where: s.id == ^other.id),
        set: [inserted_at: ~N[2099-01-01 00:00:00], locked_fields: ["name"]]
      )

      for f <- File.ls!(ctx.new_dir), do: Scanner.scan_file_sync(ctx.lib.id, Path.join(ctx.new_dir, f))

      assert Enum.all?(Library.list_books(ctx.lib.id, access: Access.all()), &(&1.series_id == other.id))
      assert Repo.get(Series, ctx.series.id).path == ctx.old_dir
    end

    test "issues split into a new folder get their own series", ctx do
      split_dir = mkdir(ctx.tmp, "Barbarian Annual (2026)")
      File.rename!(Path.join(ctx.old_dir, "Barbarian 003.cbz"), Path.join(split_dir, "Barbarian 003.cbz"))
      Scanner.scan_sync(ctx.lib.id)

      assert Repo.get(Series, ctx.series.id).path == ctx.old_dir
      assert [_, _] = live_series()
    end
  end

  describe "scan queue" do
    setup %{lib: lib, tmp: tmp} do
      write_cbz(mkdir(tmp, "Saga (2012-)"), "Saga 001.cbz")
      Scanner.scan_sync(lib.id)
      [series] = Repo.all(Stashix.Library.Series)

      scan = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(scan, :kill) end)
      %{series: series, scan: scan, state: %{table: nil, scanning: %{scan => {lib.id, :library}}, pending: %{}}}
    end

    defp scan_down(state, pid), do: Scanner.handle_info({:DOWN, make_ref(), :process, pid, :normal}, state)

    test "file scans wait for the library scan", %{lib: lib, scan: scan, state: state} do
      Phoenix.PubSub.subscribe(Stashix.PubSub, "scan:#{lib.id}")
      {:noreply, state} = Scanner.handle_cast({:scan_file, lib.id, "/missing/a.cbz"}, state)
      {:noreply, state} = Scanner.handle_cast({:scan_file, lib.id, "/missing/a.cbz"}, state)
      assert state.pending == %{lib.id => [{:file, "/missing/a.cbz"}]}
      assert_received {:scan_queue, %{items: [%{kind: :file, label: "a.cbz"}]}}
      refute_received {:scan_queue, _}, "unchanged queue is not re-broadcast"

      {:noreply, state} = scan_down(state, scan)
      assert state.scanning == %{}
      assert state.pending == %{}
      assert_received {:scan_queue, %{items: []}}
    end

    test "file scans of other libraries run straight away", %{scan: scan, state: state} do
      {:noreply, state} = Scanner.handle_cast({:scan_file, Ecto.UUID.generate(), "/missing/a.cbz"}, state)
      assert state.pending == %{}
      assert Map.keys(state.scanning) == [scan]
    end

    test "library scans wait, collapse into one and upgrade to force", %{lib: lib, state: state} do
      {:noreply, state} = Scanner.handle_cast({:scan, lib.id, false}, state)
      {:noreply, state} = Scanner.handle_cast({:scan_file, lib.id, "/missing/a.cbz"}, state)
      {:noreply, state} = Scanner.handle_cast({:scan, lib.id, true}, state)
      {:noreply, state} = Scanner.handle_cast({:scan, lib.id, false}, state)
      assert state.pending == %{lib.id => [{:library, true}, {:file, "/missing/a.cbz"}]}

      {:noreply, state} = Scanner.handle_cast({:cancel_scan, lib.id}, state)
      assert state.pending == %{lib.id => [{:file, "/missing/a.cbz"}]}
    end

    test "a queued library scan runs before queued series and file scans", ctx do
      %{lib: lib, series: series, scan: scan} = ctx
      {:noreply, state} = Scanner.handle_cast({:scan_file, lib.id, "/missing/a.cbz"}, ctx.state)
      {:noreply, state} = Scanner.handle_cast({:scan_series, series.id, false}, state)
      {:noreply, state} = Scanner.handle_cast({:scan, lib.id, false}, state)

      {:noreply, state} = scan_down(state, scan)
      assert [{library_scan, {_, :library}}] = Map.to_list(state.scanning)
      assert state.pending == %{lib.id => [{:series, series.id, false}, {:file, "/missing/a.cbz"}]}

      ref = Process.monitor(library_scan)
      assert_receive {:DOWN, ^ref, _, _, _}, 5_000
      {:noreply, state} = scan_down(state, library_scan)
      assert [{series_scan, {_, :series}}] = Map.to_list(state.scanning)

      ref = Process.monitor(series_scan)
      assert_receive {:DOWN, ^ref, _, _, _}, 5_000
      {:noreply, state} = scan_down(state, series_scan)
      assert state.pending == %{}
    end

    test "series scans wait for the library scan, file scans for both", ctx do
      %{lib: lib, series: series, scan: scan} = ctx
      {:noreply, state} = Scanner.handle_cast({:scan_file, lib.id, "/missing/a.cbz"}, ctx.state)
      {:noreply, state} = Scanner.handle_cast({:scan_series, series.id, false}, state)
      assert state.pending == %{lib.id => [{:file, "/missing/a.cbz"}, {:series, series.id, false}]}

      {:noreply, state} = scan_down(state, scan)
      assert [{series_scan, {_, :series}}] = Map.to_list(state.scanning)
      assert state.pending == %{lib.id => [{:file, "/missing/a.cbz"}]}

      ref = Process.monitor(series_scan)
      assert_receive {:DOWN, ^ref, _, _, _}, 5_000
      {:noreply, state} = scan_down(state, series_scan)
      assert state == %{table: nil, scanning: %{}, pending: %{}}
    end
  end

  describe "scan_sync/2 force rescan" do
    test "force rescan corrects manually corrupted type", %{lib: lib, tmp: tmp} do
      write_cbz(mkdir(tmp, "One-Shot"), "Standalone.cbz")
      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())
      assert book.type == "standalone"

      Library.update_book(book, %{type: "issue"})
      assert Repo.get!(Book, book.id).type == "issue"

      Scanner.scan_sync(lib.id, true)
      assert Repo.get!(Book, book.id).type == "standalone"
    end

    test "normal rescan skips unmodified files", %{lib: lib, tmp: tmp} do
      write_cbz(tmp, "My Book.cbz")
      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())
      original_updated_at = book.updated_at

      Scanner.scan_sync(lib.id)
      assert Repo.get!(Book, book.id).updated_at == original_updated_at
    end
  end

  # ── file metadata on rescan ───────────────────────────────────────────────

  @tagged_xml """
  <ComicInfo>
    <Title>Gotham Rising</Title><Number>7</Number><AlternateNumber>51</AlternateNumber>
    <Publisher>DC Comics</Publisher><Imprint>Black Label</Imprint><AgeRating>Mature 17+</AgeRating>
  </ComicInfo>
  """

  describe "edits made during a scan" do
    setup %{lib: lib, tmp: tmp} do
      dir = mkdir(tmp, "Saga (2012-)")
      write_cbz(dir, "Saga 001.cbz", extra: [{~c"ComicInfo.xml", "<ComicInfo><Title>Old</Title></ComicInfo>"}])
      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())
      write_cbz(dir, "Saga 001.cbz", extra: [{~c"ComicInfo.xml", "<ComicInfo><Title>New</Title></ComicInfo>"}])
      %{book: book}
    end

    defp set_updated_at(book, at), do: Repo.update_all(from(b in Book, where: b.id == ^book.id), set: [updated_at: at])

    test "a book changed after its file was read keeps its metadata", %{lib: lib, book: book} do
      set_updated_at(book, ~N[2099-01-01 00:00:00])
      Scanner.scan_sync(lib.id, true)
      assert Repo.get!(Book, book.id).title == "Old"
    end

    test "a book last changed before its file was read takes the file's", %{lib: lib, book: book} do
      set_updated_at(book, ~N[2000-01-01 00:00:00])
      Scanner.scan_sync(lib.id, true)
      assert Repo.get!(Book, book.id).title == "New"
    end
  end

  describe "Metadata.write_pending?/1" do
    test "is true while a write-back job waits", %{lib: lib} do
      {:ok, book} = Library.create_book(%{library_id: lib.id, type: "standalone", title: "T"})
      refute Stashix.Metadata.write_pending?(book.id)
      {:ok, _} = Stashix.Metadata.enqueue_write(book.id)
      assert Stashix.Metadata.write_pending?(book.id)
    end
  end

  describe "scan_sync/2 file metadata" do
    test "force rescan refreshes every field the file states", %{lib: lib, tmp: tmp} do
      write_cbz(mkdir(tmp, "Batman (2016)"), "Batman 001.cbz")
      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())

      write_cbz(Path.join(tmp, "Batman (2016)"), "Batman 001.cbz", extra: [{~c"ComicInfo.xml", @tagged_xml}])
      Scanner.scan_sync(lib.id, true)

      book = Book |> Repo.get!(book.id) |> Repo.preload([:publishers, :imprint])
      assert book.title == "Gotham Rising"
      assert book.issue_number == Decimal.new("7"), "file number beats the filename's 001"
      assert book.alternative_number == "51"
      assert book.age_rating == :mature
      assert [%{name: "DC Comics"}] = book.publishers
      assert book.imprint.name == "Black Label"
    end

    test "rescan keeps fields the file doesn't mention", %{lib: lib, tmp: tmp} do
      write_cbz(tmp, "My Book.cbz", extra: [{~c"ComicInfo.xml", "<ComicInfo><Title>T</Title></ComicInfo>"}])
      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())
      {:ok, _} = Library.update_book(book, %{age_rating: :teen, collection_title: "Coll"})

      Scanner.scan_sync(lib.id, true)
      assert %{age_rating: :teen, collection_title: "Coll"} = Repo.get!(Book, book.id)
    end

    test "a rescan doesn't swap a book's publisher for the folder's", %{lib: lib, tmp: tmp} do
      write_cbz(mkdir(tmp, "Folder Pub/One-Shot"), "Book.cbz")
      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())
      {:ok, pub} = Library.get_or_create_publisher("Real Pub")
      Repo.delete_all(from(bp in "book_publishers", where: bp.book_id == ^Ecto.UUID.dump!(book.id)))
      Library.link_publisher_to_book(book.id, pub.id)

      Scanner.scan_sync(lib.id, true)
      assert [%{name: "Real Pub"}] = Book |> Repo.get!(book.id) |> Repo.preload(:publishers) |> Map.get(:publishers)
    end

    test "a rescan leaves locked fields alone", %{lib: lib, tmp: tmp} do
      write_cbz(mkdir(tmp, "Batman (2016)"), "Batman 001.cbz")
      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())

      {:ok, _} =
        Library.update_book(book, %{title: "Mine", age_rating: :teen, locked_fields: ~w(title publisher age_rating)})

      tagged = String.replace(@tagged_xml, "</ComicInfo>", "<Characters>Robin</Characters></ComicInfo>")
      write_cbz(Path.join(tmp, "Batman (2016)"), "Batman 001.cbz", extra: [{~c"ComicInfo.xml", tagged}])
      Scanner.scan_sync(lib.id, true)

      book = Book |> Repo.get!(book.id) |> Repo.preload([:publishers, :characters])
      assert book.title == "Mine"
      assert book.age_rating == :teen
      assert book.publishers == []
      assert book.issue_number == Decimal.new("7"), "unlocked fields still follow the file"
      assert [%{name: "Robin"}] = book.characters
    end

    test "a locked series name survives a rescan", %{lib: lib, tmp: tmp} do
      write_cbz(mkdir(tmp, "Batman (2016)"), "Batman 001.cbz")
      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())
      series = Repo.get!(Stashix.Library.Series, book.series_id)
      {:ok, _} = Library.update_series(series, %{"name" => "The Batman", "locked_fields" => ["name"]})

      Scanner.scan_sync(lib.id, true)
      assert Repo.get!(Stashix.Library.Series, series.id).name == "The Batman"
    end

    test "a new issue takes its series' language unless the file states one", %{lib: lib, tmp: tmp} do
      folder = mkdir(tmp, "Asterix")
      write_cbz(folder, "Asterix 001.cbz")
      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())
      {:ok, _} = Library.update_series(Library.get_series!(book.series_id), %{"language" => "fr"})

      write_cbz(folder, "Asterix 002.cbz")

      write_cbz(folder, "Asterix 003.cbz",
        extra: [{~c"ComicInfo.xml", "<ComicInfo><LanguageISO>de</LanguageISO></ComicInfo>"}]
      )

      Scanner.scan_sync(lib.id)

      languages = Map.new(Library.list_books(lib.id, access: Access.all()), &{&1.issue_number, &1.language})
      assert languages[Decimal.new("2")] == "fr"
      assert languages[Decimal.new("3")] == "de"
      assert languages[Decimal.new("1")] == "en", "existing issues keep their language"
    end

    test "a queued write runs before a rescan reads the file", %{lib: lib, tmp: tmp} do
      write_cbz(tmp, "My Book.cbz")
      Scanner.scan_sync(lib.id)
      [book] = Library.list_books(lib.id, access: Access.all())

      {:ok, _} = Library.update_book(book, %{title: "Edited"})
      {:ok, job} = Stashix.Metadata.enqueue_write(book.id)

      Scanner.scan_sync(lib.id, true)

      assert Repo.get!(Book, book.id).title == "Edited"
      assert Repo.get!(Oban.Job, job.id).state == "completed"
    end
  end

  describe "scan_sync/2 RAR and 7z metadata" do
    @describetag :tmp_dir

    for {ext, tool, args} <- [{"cbr", "rar", ~w(a -ep -inul)}, {"cb7", "7z", ~w(a -bd -bso0)}] do
      @tag skip: is_nil(System.find_executable(tool)) && "#{tool} not installed"
      test "reads ComicInfo embedded in .#{ext}", %{lib: lib, tmp: tmp, tmp_dir: src} do
        File.write!(Path.join(src, "page001.jpg"), "fake")
        File.write!(Path.join(src, "ComicInfo.xml"), @tagged_xml)
        archive = Path.join(tmp, "Book.#{unquote(ext)}")

        {_, 0} =
          System.cmd(unquote(tool), unquote(args) ++ [archive, "page001.jpg", "ComicInfo.xml"], cd: src)

        Scanner.scan_sync(lib.id)
        assert [%{title: "Gotham Rising"}] = Library.list_books(lib.id, access: Access.all())
      end
    end

    test "a .cbr that is really a zip is read as a zip", %{lib: lib, tmp: tmp} do
      cbz = write_cbz(tmp, "Book.cbz", extra: [{~c"ComicInfo.xml", @tagged_xml}])
      File.rename!(cbz, Path.join(tmp, "Book.cbr"))

      Scanner.scan_sync(lib.id)
      assert [%{title: "Gotham Rising"}] = Library.list_books(lib.id, access: Access.all())
    end
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  defp mkdir(parent, name) do
    path = Path.join(parent, name)
    File.mkdir_p!(path)
    path
  end

  defp write_cbz(dir, filename, opts \\ []) do
    page_count = Keyword.get(opts, :page_count, 1)
    path = Path.join(dir, filename)

    files =
      for i <- 1..page_count do
        name = String.to_charlist("page#{String.pad_leading(to_string(i), 3, "0")}.jpg")
        {name, "fake jpeg: #{filename} page #{i}"}
      end

    files = files ++ Keyword.get(opts, :extra, [])

    {:ok, {_, data}} = :zip.create(String.to_charlist(path), files, [:memory])
    File.write!(path, data)
    path
  end
end
