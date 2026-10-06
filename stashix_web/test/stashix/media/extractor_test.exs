defmodule Stashix.Media.ExtractorTest do
  use ExUnit.Case, async: true

  alias Stashix.Media.Extractor

  setup do
    tmp = Path.join(System.tmp_dir!(), "extractor_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    %{tmp: tmp}
  end

  defp make_cbz(path, filenames) do
    entries = Enum.map(filenames, &{String.to_charlist(&1), ""})
    {:ok, _} = :zip.create(String.to_charlist(path), entries)
    path
  end

  describe "list_pages/1 — credit page filtering" do
    test "excludes scanner credit pages (z-prefix, no digits)", %{tmp: tmp} do
      cbz =
        make_cbz(Path.join(tmp, "book.cbz"), [
          "001.jpg",
          "002.jpg",
          "003.jpg",
          "zSoU-Nerd.jpg",
          "zAd-Group.png",
          "zzdelirium_dargh.png"
        ])

      assert {:ok, pages} = Extractor.list_pages(cbz)
      assert pages == ["001.jpg", "002.jpg", "003.jpg"]
    end

    test "excludes known ad pages, whatever the case or spacing", %{tmp: tmp} do
      cbz =
        make_cbz(Path.join(tmp, "book.cbz"), [
          "001.jpg",
          "002.jpg",
          "003.jpg",
          "004.jpg",
          "The Saint.jpg",
          "the saint.JPG",
          "zzz empirelogo.jpg",
          "zzz - coyoteDHC18.JPG",
          "zzz-mephisto.jpg",
          "zztag-rip3.jpg"
        ])

      assert {:ok, ["001.jpg", "002.jpg", "003.jpg", "004.jpg"]} = Extractor.list_pages(cbz)
    end

    test "keeps pages that only start with a known ad name", %{tmp: tmp} do
      cbz = make_cbz(Path.join(tmp, "book.cbz"), ["The Saint 001.jpg", "The Saint 002.jpg"])

      assert {:ok, pages} = Extractor.list_pages(cbz)
      assert length(pages) == 2
    end

    test "keeps z-prefixed pages that start with a digit after z", %{tmp: tmp} do
      cbz =
        make_cbz(Path.join(tmp, "book.cbz"), [
          "001.jpg",
          "z001.jpg"
        ])

      assert {:ok, pages} = Extractor.list_pages(cbz)
      assert "z001.jpg" in pages
    end

    test "keeps normal numbered and prefixed page names", %{tmp: tmp} do
      names = ["001.jpg", "page001.jpg", "ch01-pg001.jpg", "0010.png"]

      cbz = make_cbz(Path.join(tmp, "book.cbz"), names)

      assert {:ok, pages} = Extractor.list_pages(cbz)
      assert Enum.sort(pages) == Enum.sort(names)
    end

    test "filters credit pages nested in subdirectories", %{tmp: tmp} do
      cbz =
        make_cbz(Path.join(tmp, "book.cbz"), [
          "images/001.jpg",
          "images/zSoU-Nerd.jpg"
        ])

      assert {:ok, pages} = Extractor.list_pages(cbz)
      assert pages == ["images/001.jpg"]
    end

    test "keeps z-prefixed pages when most of the book is named that way", %{tmp: tmp} do
      names = ["Zatanna 001.jpg", "Zatanna 002.jpg", "Zatanna 003.jpg", "zzz-mephisto.jpg"]
      cbz = make_cbz(Path.join(tmp, "book.cbz"), ["cover.jpg", "The Saint.jpg" | names])

      assert {:ok, pages} = Extractor.list_pages(cbz)
      assert pages == Enum.sort(["cover.jpg" | names])
    end

    test "keeps the pages when every one is z-prefixed", %{tmp: tmp} do
      cbz = make_cbz(Path.join(tmp, "book.cbz"), ["zCredit.jpg", "zAd.png"])

      assert {:ok, pages} = Extractor.list_pages(cbz)
      assert length(pages) == 2
    end

    test "non-image files are excluded regardless of name", %{tmp: tmp} do
      cbz =
        make_cbz(Path.join(tmp, "book.cbz"), [
          "001.jpg",
          "ComicInfo.xml",
          "thumbs.db"
        ])

      assert {:ok, pages} = Extractor.list_pages(cbz)
      assert pages == ["001.jpg"]
    end

    test "treats an uppercase Z prefix the same as lowercase", %{tmp: tmp} do
      cbz = make_cbz(Path.join(tmp, "book.cbz"), ["001.jpg", "002.jpg", "ZCredits.JPG"])

      assert {:ok, ["001.jpg", "002.jpg"]} = Extractor.list_pages(cbz)
    end

    test "keeps a page named just z", %{tmp: tmp} do
      cbz = make_cbz(Path.join(tmp, "book.cbz"), ["001.jpg", "z.jpg"])

      assert {:ok, ["001.jpg", "z.jpg"]} = Extractor.list_pages(cbz)
    end

    test "hides z-prefixed pages when they tie with the rest", %{tmp: tmp} do
      cbz = make_cbz(Path.join(tmp, "book.cbz"), ["001.jpg", "zCredit.jpg"])

      assert {:ok, ["001.jpg"]} = Extractor.list_pages(cbz)
    end

    test "keeps z-prefixed pages when they outnumber the rest by one", %{tmp: tmp} do
      names = ["cover.jpg", "zeta-a.jpg", "zeta-b.jpg"]
      cbz = make_cbz(Path.join(tmp, "book.cbz"), names)

      assert {:ok, ^names} = Extractor.list_pages(cbz)
    end

    test "known ad pages do not count towards either side", %{tmp: tmp} do
      cbz =
        make_cbz(Path.join(tmp, "book.cbz"), ["001.jpg", "The Saint.jpg", "zCredit.jpg"])

      assert {:ok, ["001.jpg"]} = Extractor.list_pages(cbz)
    end

    test "hides known ad pages in a z-named book", %{tmp: tmp} do
      names = ["Zorro 01.jpg", "Zorro 02.jpg"]
      cbz = make_cbz(Path.join(tmp, "book.cbz"), ["THE SAINT.png" | names])

      assert {:ok, ^names} = Extractor.list_pages(cbz)
    end

    test "returns an empty list when only known ad pages are left", %{tmp: tmp} do
      cbz = make_cbz(Path.join(tmp, "book.cbz"), ["The Saint.jpg"])

      assert {:ok, []} = Extractor.list_pages(cbz)
    end

    test "filters known ad pages nested in subdirectories", %{tmp: tmp} do
      cbz = make_cbz(Path.join(tmp, "book.cbz"), ["images/001.jpg", "images/The Saint.jpg"])

      assert {:ok, ["images/001.jpg"]} = Extractor.list_pages(cbz)
    end

    test "ignores the folder name when looking for the z prefix", %{tmp: tmp} do
      names = ["zine/001.jpg", "zine/002.jpg"]
      cbz = make_cbz(Path.join(tmp, "book.cbz"), names)

      assert {:ok, ^names} = Extractor.list_pages(cbz)
    end

    test "non-image z files do not tip the balance", %{tmp: tmp} do
      cbz =
        make_cbz(Path.join(tmp, "book.cbz"), ["001.jpg", "zCredit.jpg", "zinfo.txt", "znotes.nfo"])

      assert {:ok, ["001.jpg"]} = Extractor.list_pages(cbz)
    end

    test "returns an empty list for an archive without images", %{tmp: tmp} do
      cbz = make_cbz(Path.join(tmp, "book.cbz"), ["ComicInfo.xml"])

      assert {:ok, []} = Extractor.list_pages(cbz)
    end
  end

  describe "page count and page lookup" do
    test "count and index skip the hidden pages", %{tmp: tmp} do
      path = Path.join(tmp, "book.cbz")

      entries = [
        {~c"001.jpg", "one"},
        {~c"002.jpg", "two"},
        {~c"The Saint.jpg", "ad"},
        {~c"zzz-mephisto.jpg", "credit"}
      ]

      {:ok, _} = :zip.create(String.to_charlist(path), entries)

      assert Extractor.get_page_count(path) == 2
      assert {:ok, "two"} = Extractor.get_page(path, 1)
      assert {:error, :page_not_found} = Extractor.get_page(path, 2)
    end

    test "count is zero for an unreadable file", %{tmp: tmp} do
      path = Path.join(tmp, "broken.cbz")
      File.write!(path, "not a zip")

      assert Extractor.get_page_count(path) == 0
    end
  end

  describe "list_pages/1 — other archive formats" do
    @names ["001.jpg", "002.jpg", "003.jpg", "The Saint.jpg", "zzz - coyoteDHC18.JPG"]
    @z_names ["Zatanna 001.jpg", "Zatanna 002.jpg", "cover.jpg"]

    defp make_archive(tmp, cmd, args, out, names) do
      src = Path.join(tmp, "src_#{:erlang.unique_integer([:positive])}")
      File.mkdir_p!(src)
      Enum.each(names, &File.write!(Path.join(src, &1), "x"))
      path = Path.join(tmp, out)
      {_, 0} = System.cmd(cmd, args ++ [path | names], cd: src, stderr_to_stdout: true)
      path
    end

    if System.find_executable("rar") && System.find_executable("unrar") do
      test "cbr hides credit and ad pages", %{tmp: tmp} do
        cbr = make_archive(tmp, "rar", ["a", "-inul"], "book.cbr", @names)

        assert {:ok, ["001.jpg", "002.jpg", "003.jpg"]} = Extractor.list_pages(cbr)
      end

      test "cbr keeps the pages of a z-named book", %{tmp: tmp} do
        cbr = make_archive(tmp, "rar", ["a", "-inul"], "book.cbr", @z_names)

        assert {:ok, @z_names} = Extractor.list_pages(cbr)
      end
    end

    if System.find_executable("7z") do
      test "cb7 hides credit and ad pages", %{tmp: tmp} do
        cb7 = make_archive(tmp, "7z", ["a", "-t7z"], "book.cb7", @names)

        assert {:ok, ["001.jpg", "002.jpg", "003.jpg"]} = Extractor.list_pages(cb7)
      end

      test "cb7 keeps the pages of a z-named book", %{tmp: tmp} do
        cb7 = make_archive(tmp, "7z", ["a", "-t7z"], "book.cb7", @z_names)

        assert {:ok, @z_names} = Extractor.list_pages(cb7)
      end
    end

    test "epub hides credit and ad pages", %{tmp: tmp} do
      epub = make_cbz(Path.join(tmp, "book.epub"), ["OEBPS/chapter.xhtml" | @names])

      assert {:ok, ["001.jpg", "002.jpg", "003.jpg"]} = Extractor.list_pages(epub)
    end

    test "unsupported formats are an error", %{tmp: tmp} do
      assert {:error, :unsupported_format} = Extractor.list_pages(Path.join(tmp, "book.txt"))
    end
  end
end
