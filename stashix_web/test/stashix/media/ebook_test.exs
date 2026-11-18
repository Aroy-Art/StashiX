# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Media.EbookTest do
  use ExUnit.Case, async: true

  import Stashix.EbookFixtures

  alias Stashix.Media.{ContentKind, Fb2, Formats, Mobi, Thumbnail}

  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0, "fake jpeg">>

  setup do
    tmp = Path.join(System.tmp_dir!(), "ebook_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    %{tmp: tmp}
  end

  describe "Formats" do
    test "reads the format off the name, .fb2.zip included" do
      assert Formats.format("/x/Dune.AZW3") == :azw3
      assert Formats.format("/x/Dune.fb2.zip") == :fbz
      assert Formats.format("/x/Dune.fbz") == :fbz
      assert Formats.format("/x/Dune.zip") == nil
      assert Formats.stem("/x/Dune Messiah.fb2.zip") == "Dune Messiah"
      assert Formats.stem("/x/Dune.cbz") == "Dune"
      assert ".fb2.zip" in Formats.extensions()
    end
  end

  describe "Mobi" do
    test "metadata from the EXTH records", %{tmp: tmp} do
      path =
        make_mobi(Path.join(tmp, "b.mobi"),
          title: "Moby Dick",
          exth: [
            {100, "Herman Melville"},
            {101, "Harper & Brothers"},
            {103, "<p>The <b>whale</b>.</p>"},
            {104, "9780142437247"},
            {105, "Sea stories"},
            {106, "1851-10-18T00:00:00+00:00"},
            {524, "en-US"}
          ]
        )

      assert %{
               title: "Moby Dick",
               credits: [%{creator: "Herman Melville", roles: ["Writer"]}],
               publisher: "Harper & Brothers",
               summary: "The whale .",
               isbn: "9780142437247",
               genres: ["Sea stories"],
               year: 1851,
               cover_date: ~D[1851-10-18],
               language: "en"
             } = Mobi.metadata(path)
    end

    test "the EXTH title wins over the full name; several authors split", %{tmp: tmp} do
      path = make_mobi(Path.join(tmp, "b.azw3"), title: "Old", exth: [{503, "New"}, {100, "A. One & B. Two"}])

      assert %{title: "New", credits: [%{creator: "A. One"}, %{creator: "B. Two"}]} = Mobi.metadata(path)
    end

    test "cover, length, DRM and kind", %{tmp: tmp} do
      path = make_mobi(Path.join(tmp, "b.mobi"), cover: @jpeg, text: String.duplicate("x", 4500))

      assert {:ok, @jpeg} = Mobi.cover(path)
      assert Mobi.location_count(path) == 3
      refute Mobi.drm?(path)
      assert ContentKind.detect(path) == :text

      locked = make_mobi(Path.join(tmp, "locked.azw"), encryption: 2)
      assert Mobi.drm?(locked)
      assert {:error, :no_cover} = Mobi.cover(locked)
    end

    test "anything else is not a Kindle book", %{tmp: tmp} do
      path = Path.join(tmp, "kfx.azw")
      File.write!(path, "CONT" <> :binary.copy(<<0>>, 200))
      assert {:error, :not_mobi} = Mobi.header(path)
      assert Mobi.metadata(path) == %{}
      refute Mobi.drm?(path)
    end

    test "the thumbnail is the cover", %{tmp: tmp} do
      path = make_mobi(Path.join(tmp, "b.mobi"), cover: @jpeg)
      dest = Path.join(tmp, "thumb.jpg")
      assert {:ok, ^dest} = Thumbnail.generate(path, dest)
      assert File.read!(dest) == @jpeg
    end
  end

  describe "Fb2" do
    test "metadata from the description", %{tmp: tmp} do
      path = make_fb2(Path.join(tmp, "b.fb2"), sequence: {"Elliot Family", "2"})

      assert %{
               title: "Persuasion",
               credits: [%{creator: "Jane Austen", roles: ["Writer"]}],
               series: "Elliot Family",
               summary: "A second chance.",
               genres: ["prose_classic"],
               language: "en",
               year: 1817,
               publisher: "John Murray",
               isbn: "9780141439688"
             } = meta = Fb2.metadata(path)

      assert Decimal.equal?(meta.issue_number, 2)
    end

    test "zipped, with a cover", %{tmp: tmp} do
      path = make_fb2(Path.join(tmp, "b.fb2.zip"), zip: true, cover: @jpeg, title: "Emma")

      assert {:ok, xml} = Fb2.read(path)
      assert xml =~ "<FictionBook"
      assert %{title: "Emma"} = Fb2.metadata(path)
      assert {:ok, @jpeg} = Fb2.cover(path)
      assert Fb2.location_count(path) >= 1
      assert ContentKind.detect(path) == :text
    end

    test "no cover", %{tmp: tmp} do
      assert {:error, :no_cover} = Fb2.cover(make_fb2(Path.join(tmp, "b.fb2")))
    end
  end
end
