# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.ScannerOpfTest do
  use Stashix.DataCase, async: false

  import Stashix.EpubFixtures

  alias Stashix.{Library, Repo, Scanner}
  alias Stashix.Library.{Book, Series}

  setup do
    tmp = Path.join(System.tmp_dir!(), "stashix_opf_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    thumbs = Path.join(System.tmp_dir!(), "stashix_test_thumbs_#{System.unique_integer([:positive])}")
    Application.put_env(:stashix, :thumbnail_dir, thumbs)

    on_exit(fn ->
      Application.delete_env(:stashix, :thumbnail_dir)
      File.rm_rf!(tmp)
      File.rm_rf(thumbs)
    end)

    {:ok, lib} = Library.create_library(%{name: "Books", root_path: tmp, kind: :books})
    %{lib: lib, tmp: tmp}
  end

  defp opf(attrs) do
    series =
      if s = attrs[:series],
        do:
          ~s(<meta name="calibre:series" content="#{s}"/><meta name="calibre:series_index" content="#{attrs[:index] || 1}"/>),
        else: ""

    """
    <?xml version='1.0' encoding='utf-8'?>
    <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
        <dc:title>#{attrs[:title]}</dc:title>
        <dc:creator opf:file-as="Herbert, Frank" opf:role="aut">Frank Herbert</dc:creator>
        <dc:subject>Science Fiction</dc:subject>
        <dc:identifier opf:scheme="ISBN">9780441013593</dc:identifier>
        <meta name="calibre:title_sort" content="#{attrs[:sort] || attrs[:title]}"/>
        <meta name="calibre:rating" content="8"/>
        #{series}
      </metadata>
    </package>
    """
  end

  defp book!(title), do: Book |> Repo.get_by!(title: title) |> Repo.preload([:files, :series, :tags, credits: :creator])

  test "a Calibre library folder: one book per folder, series from the OPF", %{lib: lib, tmp: tmp} do
    dir = Path.join([tmp, "Frank Herbert", "Dune (12)"])
    File.mkdir_p!(dir)
    make_epub(Path.join(dir, "Dune - Frank Herbert.epub"), [{:text, "A beginning is a very delicate time."}])
    Stashix.EbookFixtures.make_mobi(Path.join(dir, "Dune - Frank Herbert.mobi"))
    File.write!(Path.join(dir, "metadata.opf"), opf(title: "Dune", series: "Dune Chronicles", index: 1))
    File.write!(Path.join(dir, "cover.jpg"), Image.new!(20, 30, color: :red) |> Image.write!(:memory, suffix: ".jpg"))

    other = Path.join([tmp, "Frank Herbert", "Whipping Star (13)"])
    File.mkdir_p!(other)
    make_epub(Path.join(other, "Whipping Star - Frank Herbert.epub"), [{:text, "Text."}])
    File.write!(Path.join(other, "metadata.opf"), opf(title: "Whipping Star"))

    Scanner.scan_sync(lib.id)

    dune = book!("Dune")
    assert Enum.map(dune.files, & &1.format) |> Enum.sort() == [:epub, :mobi]
    assert %Series{name: "Dune Chronicles", path: nil} = dune.series
    assert {dune.type, Decimal.to_integer(dune.issue_number)} == {"issue", 1}
    assert {dune.sort_title, dune.rating, dune.isbn} == {"Dune", 4.0, "9780441013593"}
    assert Enum.map(dune.credits, &{&1.creator.name, &1.role}) == [{"Frank Herbert", :Writer}]
    assert Enum.map(dune.tags, & &1.name) == ["Science Fiction"]

    # Calibre's cover.jpg is the cover.
    assert Scanner.find_sidecar_image(hd(dune.files).path) == Path.join(dir, "cover.jpg")
    assert Repo.preload(dune, :cover).cover

    star = book!("Whipping Star")
    assert {star.type, star.series_id} == {"standalone", nil}

    # Neither the author folder nor the book folders became series.
    assert Repo.all(from s in Series, where: is_nil(s.deleted_at), select: s.name) == ["Dune Chronicles"]
  end

  test "Calibre's Save to disk: a <book>.opf next to the file", %{lib: lib, tmp: tmp} do
    dir = Path.join([tmp, "Herbert, Frank", "Dune"])
    File.mkdir_p!(dir)
    make_epub(Path.join(dir, "Dune - Frank Herbert.epub"), [{:text, "Text."}])
    File.write!(Path.join(dir, "Dune - Frank Herbert.opf"), opf(title: "Dune", series: "Dune Chronicles"))

    Scanner.scan_sync(lib.id)
    assert book!("Dune").series.name == "Dune Chronicles"
  end

  test "an OPF edited on its own is picked up by the next scan", %{lib: lib, tmp: tmp} do
    dir = Path.join([tmp, "Frank Herbert", "Dune (12)"])
    File.mkdir_p!(dir)
    make_epub(Path.join(dir, "Dune - Frank Herbert.epub"), [{:text, "Text."}])
    opf_path = Path.join(dir, "metadata.opf")
    File.write!(opf_path, opf(title: "Dune"))
    Scanner.scan_sync(lib.id)

    File.write!(opf_path, opf(title: "Dune Messiah", series: "Dune Chronicles", index: 2))
    # Newer than the import, as an edit would be.
    File.touch!(opf_path, System.os_time(:second) + 5)

    Scanner.scan_sync(lib.id)
    messiah = book!("Dune Messiah")
    assert messiah.series.name == "Dune Chronicles"
    assert Decimal.to_integer(messiah.issue_number) == 2
  end

  test "Stashix's own sidecars still win over the OPF", %{lib: lib, tmp: tmp} do
    dir = Path.join([tmp, "Frank Herbert", "Dune (12)"])
    File.mkdir_p!(dir)
    epub = make_epub(Path.join(dir, "Dune - Frank Herbert.epub"), [{:text, "Text."}])
    File.write!(Path.join(dir, "metadata.opf"), opf(title: "Dune"))

    File.write!(
      Stashix.Metadata.Sidecar.path(epub, :comicinfo),
      ~s|<?xml version="1.0"?><ComicInfo><Title>Dune (edited)</Title></ComicInfo>|
    )

    Scanner.scan_sync(lib.id)
    assert book!("Dune (edited)").rating == 4.0
  end

  test "folders without an OPF keep their folder series", %{lib: lib, tmp: tmp} do
    dir = Path.join(tmp, "Saga")
    File.mkdir_p!(dir)
    make_epub(Path.join(dir, "Saga 001.epub"), [{:text, "Text."}])

    Scanner.scan_sync(lib.id)
    assert Repo.one!(from s in Series, select: s.name) == "Saga"
  end
end
