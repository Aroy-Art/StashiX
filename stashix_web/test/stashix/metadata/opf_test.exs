# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Metadata.Format.OpfTest do
  use ExUnit.Case, async: true

  alias Stashix.Metadata.Format.Opf

  @calibre File.read!("test/support/fixtures/opf/calibre_metadata.opf")

  test "a Calibre metadata.opf" do
    assert {:ok, r} = Opf.parse(@calibre)

    assert r.title == "Warcross"
    assert r.sort_title == "Warcross"
    assert r.credits == [%{creator: "Marie Lu", roles: ["Writer"]}]
    assert r.series == "Warcross"
    assert Decimal.equal?(r.issue_number, 1)
    assert r.publisher == "Penguin"
    assert r.language == "en"
    assert {r.cover_date, r.year} == {~D[2017-09-12], 2017}
    assert r.rating == 5.0
    assert r.isbn == "9780399547966"
    assert Enum.sort(r.tags) == ["Cyberpunk", "Fiction", "Girl", "Science Fiction"]
    assert r.summary =~ ~r/^From #1 New York Times bestselling author Marie Lu/
    refute r.summary =~ "<"

    assert Enum.sort_by(r.external_ids, & &1.source) == [
             %{source: "Amazon", source_id: "0399547967", is_primary: false},
             %{source: "Google Books", source_id: "II_fDQAAQBAJ", is_primary: false}
           ]
  end

  test "OPF 3: refines, collections and urn identifiers" do
    opf = """
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>The Fellowship of the Ring</dc:title>
        <dc:creator id="c1">J. R. R. Tolkien</dc:creator>
        <meta refines="#c1" property="role" scheme="marc:relators">aut</meta>
        <dc:contributor id="c2">Alan Lee</dc:contributor>
        <meta refines="#c2" property="role" scheme="marc:relators">ill</meta>
        <dc:contributor id="c3">calibre</dc:contributor>
        <meta refines="#c3" property="role" scheme="marc:relators">bkp</meta>
        <dc:identifier>urn:isbn:9780261102354</dc:identifier>
        <dc:identifier>goodreads:34</dc:identifier>
        <dc:date>1954</dc:date>
        <meta property="belongs-to-collection" id="s1">The Lord of the Rings</meta>
        <meta refines="#s1" property="group-position">1.5</meta>
        <meta property="calibre:title_sort">Fellowship of the Ring, The</meta>
      </metadata>
    </package>
    """

    assert {:ok, r} = Opf.parse(opf)

    assert r.credits == [
             %{creator: "Alan Lee", roles: ["Illustrator"]},
             %{creator: "J. R. R. Tolkien", roles: ["Writer"]}
           ]

    assert r.series == "The Lord of the Rings"
    assert Decimal.equal?(r.issue_number, Decimal.new("1.5"))
    assert r.isbn == "9780261102354"
    assert r.external_ids == [%{source: "Goodreads", source_id: "34", is_primary: false}]
    assert {r.year, r.cover_date} == {1954, ~D[1954-01-01]}
    assert r.sort_title == "Fellowship of the Ring, The"
  end

  test "unknown dates, no series, no rating" do
    opf = """
    <package xmlns="http://www.idpf.org/2007/opf"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
      <dc:title>Alone</dc:title><dc:date>0101-01-01T00:00:00+00:00</dc:date>
      <meta name="calibre:series_index" content="3"/><meta name="calibre:rating" content="0"/>
    </metadata></package>
    """

    assert {:ok, r} = Opf.parse(opf)
    assert r == %{title: "Alone"}
  end

  test "broken XML is an error, not a crash" do
    assert {:error, _} = Opf.parse("<package><metadata>")
  end

  @tag :tmp_dir
  test "sidecar_path/1 prefers the book's own .opf over the folder's", %{tmp_dir: tmp} do
    book = Path.join(tmp, "Dune - Frank Herbert.epub")
    File.write!(book, "")
    assert Opf.sidecar_path(book) == nil

    File.write!(Path.join(tmp, "metadata.opf"), "")
    assert Opf.sidecar_path(book) == Path.join(tmp, "metadata.opf")

    File.write!(Path.join(tmp, "Dune - Frank Herbert.opf"), "")
    assert Opf.sidecar_path(book) == Path.join(tmp, "Dune - Frank Herbert.opf")
  end
end
