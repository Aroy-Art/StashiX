# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Media.EpubTest do
  use ExUnit.Case, async: true

  import Stashix.EpubFixtures

  alias Stashix.Media.{ContentKind, Epub, Extractor}

  setup do
    tmp = Path.join(System.tmp_dir!(), "epub_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    %{tmp: tmp}
  end

  @prose String.duplicate("It was a dark and stormy night; the rain fell in torrents. ", 60)

  test "reads entries through the zip directory", %{tmp: tmp} do
    epub = make_epub(Path.join(tmp, "b.epub"), [{:text, "Hello"}])

    assert {:ok, entries} = Epub.entries(epub)
    assert entries["OEBPS/content.opf"] > 0
    assert {:ok, "application/epub+zip"} = Epub.read(epub, "mimetype")
    assert {:ok, xhtml} = Epub.read(epub, "OEBPS/text/ch1.xhtml")
    assert xhtml =~ "Hello"
    assert {:error, :not_found} = Epub.read(epub, "OEBPS/nope.xhtml")
  end

  test "parses the package: spine in order, hrefs from the zip root", %{tmp: tmp} do
    epub = make_epub(Path.join(tmp, "b.epub"), [{:text, "One"}, {:text, "Two"}])

    assert {:ok, %{opf: "OEBPS/content.opf", layout: nil, spine: spine}} = Epub.package(epub)
    assert Enum.map(spine, & &1.item.href) == ["OEBPS/text/ch1.xhtml", "OEBPS/text/ch2.xhtml"]
  end

  test "prose is text", %{tmp: tmp} do
    epub = make_epub(Path.join(tmp, "novel.epub"), [{:image, "cover.jpg"}, {:text, @prose}, {:text, @prose}])
    assert Epub.content_kind(epub) == :text
    assert ContentKind.detect(epub) == :text
    assert Epub.pages(epub) == nil
  end

  test "picture-only spine documents are image pages, in spine order", %{tmp: tmp} do
    # Names sort the other way round, so this is the spine's order, not the zip's.
    epub = make_epub(Path.join(tmp, "manga.epub"), [{:image, "p9.jpg"}, {:image, "p1.jpg"}, {:image, "p5.jpg"}])

    assert Epub.content_kind(epub) == :images
    assert Epub.pages(epub) == ["OEBPS/images/p9.jpg", "OEBPS/images/p1.jpg", "OEBPS/images/p5.jpg"]
    assert {:ok, ["OEBPS/images/p9.jpg" | _]} = Extractor.list_pages(epub)
    assert {:ok, "jpeg:p1.jpg"} = Extractor.get_page(epub, 1)
  end

  test "fixed layout is images even with text in it", %{tmp: tmp} do
    epub = make_epub(Path.join(tmp, "fxl.epub"), [{:text, @prose}], layout: "pre-paginated")
    assert Epub.content_kind(epub) == :images
  end

  test "location count follows the size of the linear text", %{tmp: tmp} do
    epub = make_epub(Path.join(tmp, "novel.epub"), List.duplicate({:text, @prose}, 5))
    {:ok, sizes} = Epub.entries(epub)
    total = for i <- 1..5, reduce: 0, do: (acc -> acc + sizes["OEBPS/text/ch#{i}.xhtml"])
    assert Epub.location_count(epub) == ceil(total / 1500)
  end

  test "a broken file is unknown, not a crash", %{tmp: tmp} do
    path = Path.join(tmp, "broken.epub")
    File.write!(path, "not a zip")
    assert Epub.content_kind(path) == nil
    assert {:error, _} = Epub.package(path)
    assert Epub.location_count(path) == 0
  end
end
