# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Media.ContentKindTest do
  use ExUnit.Case, async: true

  import Stashix.PdfFixtures

  alias Stashix.Media.ContentKind

  setup do
    tmp = Path.join(System.tmp_dir!(), "content_kind_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    %{tmp: tmp}
  end

  @prose Enum.map_join(1..40, "\n", fn i -> "Line #{i} of a page that is mostly running text." end)

  test "comic archives are images, by extension" do
    for ext <- ~w(cbz cbr cb7), do: assert(ContentKind.detect("/nowhere/book.#{ext}") == :images)
  end

  test "EPUB is unknown until the EPUB reader detects it" do
    assert ContentKind.detect("/nowhere/book.epub") == nil
  end

  if System.find_executable("pdftotext") do
    test "a PDF full of text is text", %{tmp: tmp} do
      pdf = make_pdf(Path.join(tmp, "novel.pdf"), List.duplicate({612, 792, @prose}, 3))
      assert ContentKind.detect(pdf) == :text
    end

    test "a PDF without text is images", %{tmp: tmp} do
      pdf = make_pdf(Path.join(tmp, "scan.pdf"), List.duplicate({612, 792}, 3))
      assert ContentKind.detect(pdf) == :images
    end

    test "a little text per page is unknown", %{tmp: tmp} do
      bubbles = "HEY! WATCH OUT FOR THAT TRUCK!\nWHAT TRUCK?\nTHAT ONE, RIGHT THERE!"
      pdf = make_pdf(Path.join(tmp, "ocr.pdf"), List.duplicate({612, 792, bubbles}, 3))
      assert ContentKind.detect(pdf) == nil
    end

    test "an unreadable PDF is unknown", %{tmp: tmp} do
      path = Path.join(tmp, "broken.pdf")
      File.write!(path, "not a pdf")
      assert ContentKind.detect(path) == nil
    end
  end
end
