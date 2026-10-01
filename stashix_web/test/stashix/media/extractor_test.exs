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
          "zSoU-Nerd.jpg",
          "zAd-Group.png",
          "zzdelirium_dargh.png"
        ])

      assert {:ok, pages} = Extractor.list_pages(cbz)
      assert pages == ["001.jpg", "002.jpg"]
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

    test "returns empty list when all pages are credits", %{tmp: tmp} do
      cbz =
        make_cbz(Path.join(tmp, "book.cbz"), [
          "zCredit.jpg",
          "zAd.png"
        ])

      assert {:ok, []} = Extractor.list_pages(cbz)
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
  end
end
