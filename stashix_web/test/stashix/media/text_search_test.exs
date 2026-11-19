# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Media.TextSearchTest do
  use ExUnit.Case, async: true

  import Stashix.EpubFixtures
  import Stashix.PdfFixtures

  alias Stashix.Media.TextSearch

  @moduletag :tmp_dir

  test "EPUB hits are numbered per section, in spine order", %{tmp_dir: tmp} do
    epub =
      make_epub(Path.join(tmp, "a.epub"), [
        {:text, "Call me Ishmael. A whale, a WHALE!"},
        {:image, "plate.jpg"},
        {:text, "No more whales."}
      ])

    assert {:ok, [first, second, third]} = TextSearch.search(:epub, epub, "whale")
    assert %{section: 0, n: 0, href: "OEBPS/text/ch1.xhtml", before: "Call me Ishmael. A ", match: "whale"} = first
    assert %{section: 0, n: 1, match: "WHALE", after: "!"} = second
    # Section 1 (the picture) still counts.
    assert %{section: 2, n: 0, before: "No more ", match: "whale", after: "s."} = third
  end

  test "matches like the reader does: no case, accents, format characters or styles", %{tmp_dir: tmp} do
    epub =
      make_epub(Path.join(tmp, "b.epub"), [
        {:text, "Café   au\nlait, cafe­teria<style>.cafe { }</style>"},
        {:text, "aaa"}
      ])

    assert {:ok, hits} = TextSearch.search(:epub, epub, "CAFE au lait")
    assert [%{match: "Café au lait"}] = hits

    assert {:ok, [%{match: "Café"}, %{match: "cafe", after: "teria"}]} = TextSearch.search(:epub, epub, "cafe")
    # Overlapping matches count, as in foliate-js.
    assert {:ok, [%{n: 0}, %{n: 1}]} = TextSearch.search(:epub, epub, "aa")
    assert {:ok, []} = TextSearch.search(:epub, epub, "   ")
  end

  test "context is cut to 40 characters each side", %{tmp_dir: tmp} do
    text = String.duplicate("a", 100) <> "needle" <> String.duplicate("b", 100)
    epub = make_epub(Path.join(tmp, "c.epub"), [{:text, text}])

    assert {:ok, [hit]} = TextSearch.search(:epub, epub, "needle")
    assert hit.before == String.duplicate("a", 40)
    assert hit.after == String.duplicate("b", 40)
  end

  test "excerpts space out blocks that meet with nothing between them", %{tmp_dir: tmp} do
    epub = make_epub(Path.join(tmp, "d.epub"), [{:text, "The bow.</p><p>A whale.</p>\n<p>Next.</p><p>Last"}])

    assert {:ok, [hit]} = TextSearch.search(:epub, epub, "whale")
    assert {hit.before, hit.match, hit.after} == {"The bow. A ", "whale", ". Next. Last"}

    # Matching still sees the text run together, as foliate-js does.
    assert {:ok, [%{before: "The ", match: "bow. A", after: " whale. Next. Last"}]} =
             TextSearch.search(:epub, epub, "bow.a")
  end

  test "other formats are left to the reader" do
    assert {:error, :unsupported} = TextSearch.search(:mobi, "/nowhere/book.mobi", "whale")
  end

  if System.find_executable("pdftotext") do
    test "PDF hits are pages", %{tmp_dir: tmp} do
      pdf = make_pdf(Path.join(tmp, "a.pdf"), [{612, 792, "Call me Ishmael."}, {612, 792}, {612, 792, "The whale."}])

      assert {:ok, [%{section: 2, n: 0, match: "whale", before: "The "}]} = TextSearch.search(:pdf, pdf, "whale")
    end

    test "an unreadable PDF is an error", %{tmp_dir: tmp} do
      path = Path.join(tmp, "broken.pdf")
      File.write!(path, "not a pdf")
      assert {:error, _} = TextSearch.search(:pdf, path, "whale")
    end
  end
end
