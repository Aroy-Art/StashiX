# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Metadata.FileWriterTest do
  use Stashix.DataCase, async: false

  import Stashix.MetadataFixtures

  alias Stashix.{Library, Repo}
  alias Stashix.Library.BookFile
  alias Stashix.Metadata.{Parser, Importer}
  alias Stashix.Metadata.Record
  alias Stashix.Metadata.Writer.FileWriter
  alias Stashix.Metadata.Format.{ComicInfo, MetronInfo}

  setup do
    tmp = Path.join(System.tmp_dir!(), "stashix_writer_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    lib = library_fixture(tmp)
    series = series_fixture(lib, %{format: :"Single Issue", volume: 3})

    book =
      book_fixture(lib, series, %{
        title: "I Am Gotham, Part One",
        summary: "A <b>bold</b> & brave tale",
        cover_date: ~D[2016-08-01],
        upc: "123"
      })

    {:ok, _} =
      Importer.replace_book_metadata(book, %{
        stories: [%{name: "I Am Gotham, Part One", external_id: nil}],
        credits: [%{creator: "Tom King", roles: ["Writer"]}, %{creator: "David Finch", roles: ["Penciller", "Cover"]}],
        characters: [%{name: "Batman", external_id: "10"}],
        genres: ["Super-Hero"],
        external_ids: [%{source: "Metron", source_id: "111", is_primary: true}]
      })

    {:ok, pub} = Library.get_or_create_publisher("DC Comics")
    Library.link_publisher_to_book(book.id, pub.id)

    %{tmp: tmp, lib: lib, book: book}
  end

  defp add_file(book, path, format) do
    stat = File.stat!(path)

    {:ok, f} =
      Library.create_book_file(%{
        book_id: book.id,
        path: path,
        format: format,
        file_size: stat.size,
        file_hash: "x",
        last_modified: NaiveDateTime.from_erl!(stat.mtime)
      })

    f
  end

  test "MetronInfo round-trips through the parser", %{book: book} do
    xml = MetronInfo.build(Record.from_book(book))
    assert xml =~ "&lt;b&gt;bold&lt;/b&gt; &amp; brave"

    path = Path.join(System.tmp_dir!(), "rt_#{System.unique_integer([:positive])}.cbz")
    cbz_fixture(path, [{~c"MetronInfo.xml", xml}])
    on_exit(fn -> File.rm(path) end)

    m = Parser.parse_comicinfo(path)
    assert m.series == "Batman"
    assert m.issue_number == Decimal.new(1)
    assert m.title == "I Am Gotham, Part One"
    assert m.summary == "A <b>bold</b> & brave tale"
    assert m.publisher == "DC Comics"
    assert m.cover_date == ~D[2016-08-01]
    assert m.upc == "123"
    assert m.series_format == "Single Issue"
    assert %{creator: "David Finch", roles: roles} = Enum.find(m.credits, &(&1.creator == "David Finch"))
    assert Enum.sort(roles) == ["Cover", "Penciller"]
    assert [%{source: "Metron", source_id: "111"}] = m.external_ids
  end

  test "edited title leads the stories and survives a round-trip", %{book: book} do
    {:ok, book} = Library.update_book(book, %{title: "Gotham Rising"})

    xml = MetronInfo.build(Record.from_book(book))
    assert xml =~ ~r{<Stories>\s*<Story>Gotham Rising</Story>\s*<Story>I Am Gotham, Part One</Story>}
    assert ComicInfo.build(Record.from_book(book)) =~ "<Title>Gotham Rising</Title>"

    path = Path.join(System.tmp_dir!(), "rt_#{System.unique_integer([:positive])}.cbz")
    cbz_fixture(path, [{~c"MetronInfo.xml", xml}])
    on_exit(fn -> File.rm(path) end)

    assert Parser.parse_comicinfo(path).title == "Gotham Rising"
  end

  test "title already among the stories is moved first, not duplicated", %{book: book} do
    {:ok, _} =
      Importer.replace_book_metadata(book, %{
        stories: [%{name: "Prologue", external_id: nil}, %{name: "I Am Gotham, Part One", external_id: nil}]
      })

    xml = book |> Repo.reload!() |> Record.from_book() |> MetronInfo.build()
    assert xml =~ ~r{<Stories>\s*<Story>I Am Gotham, Part One</Story>\s*<Story>Prologue</Story>\s*</Stories>}
  end

  test "ComicInfo compat copy maps credits to fields", %{book: book} do
    xml = ComicInfo.build(Record.from_book(book))
    assert xml =~ "<Writer>Tom King</Writer>"
    assert xml =~ "<CoverArtist>David Finch</CoverArtist>"
    assert xml =~ "<Title>I Am Gotham, Part One</Title>"
  end

  test "CBZ is rebuilt with metadata, pages kept, old XML replaced", %{tmp: tmp, book: book} do
    path =
      cbz_fixture(Path.join(tmp, "Batman 001.cbz"), [{~c"ComicInfo.xml", "<ComicInfo><Title>old</Title></ComicInfo>"}])

    File.chmod!(path, 0o640)
    file = add_file(book, path, :cbz)

    assert :ok = FileWriter.write_file(book, file, %{"write_comicinfo" => true})

    {:ok, entries} = :zip.extract(String.to_charlist(path), [:memory])
    by_name = Map.new(entries, fn {n, d} -> {to_string(n), d} end)

    assert by_name["001.jpg"] == "page-one"
    assert by_name["sub/003.png"] == "page-three"
    assert by_name["MetronInfo.xml"] =~ "<MetronInfo"
    assert by_name["ComicInfo.xml"] =~ "<Title>I Am Gotham, Part One</Title>"
    assert Enum.count(entries, fn {n, _} -> String.downcase(to_string(n)) == "comicinfo.xml" end) == 1

    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o640
    refute File.exists?(Path.join(tmp, ".Batman 001.cbz.stashix-tmp"))

    # BookFile refreshed so the scanner doesn't see a change
    updated = Repo.get!(BookFile, file.id)
    assert updated.file_size == File.stat!(path).size
    assert updated.file_hash != "x"
  end

  test "non-CBZ formats get a sidecar that the parser prefers", %{tmp: tmp, book: book} do
    path = Path.join(tmp, "Batman 001.cbr")
    File.write!(path, "not really rar")
    file = add_file(book, path, :cbr)

    assert :ok = FileWriter.write_file(book, file, %{"write_comicinfo" => true})
    assert File.read!(Path.join(tmp, "Batman 001.xml")) =~ "<MetronInfo"
    assert File.read!(path) == "not really rar"

    assert %{title: "I Am Gotham, Part One", series: "Batman"} = Parser.parse_comicinfo(path)
  end

  test "an existing sidecar next to a CBZ is rewritten so it can't shadow the embed", %{tmp: tmp, book: book} do
    path = cbz_fixture(Path.join(tmp, "Batman 001.cbz"), [])
    sidecar = Path.join(tmp, "Batman 001.xml")
    File.write!(sidecar, "<ComicInfo><Title>stale</Title></ComicInfo>")
    file = add_file(book, path, :cbz)

    {:ok, book} = Library.update_book(book, %{title: "Gotham Rising"})
    assert :ok = FileWriter.write_file(book, file, %{"write_comicinfo" => true})

    assert File.read!(sidecar) =~ "<MetronInfo"
    assert %{title: "Gotham Rising"} = Parser.parse_comicinfo(path)
  end

  test "no sidecar is created next to a CBZ that had none", %{tmp: tmp, book: book} do
    path = cbz_fixture(Path.join(tmp, "Batman 001.cbz"), [])
    assert :ok = FileWriter.write_file(book, add_file(book, path, :cbz), %{"write_comicinfo" => false})
    refute File.exists?(Path.join(tmp, "Batman 001.xml"))
  end

  test "an edited year survives even when the cover date disagrees", %{tmp: tmp, book: book} do
    path = cbz_fixture(Path.join(tmp, "Batman 001.cbz"), [])
    {:ok, book} = Library.update_book(book, %{year: 2017})
    assert :ok = FileWriter.write_file(book, add_file(book, path, :cbz), %{"write_comicinfo" => true})

    assert %{year: 2017, cover_date: ~D[2016-08-01]} = Parser.parse_comicinfo(path)
  end

  test "ComicInfo is written in the configured version", %{tmp: tmp, book: book} do
    path = cbz_fixture(Path.join(tmp, "Batman 001.cbz"), [])
    settings = %{"write_comicinfo" => true, "comicinfo_version" => "2.1"}
    assert :ok = FileWriter.write_file(book, add_file(book, path, :cbz), settings)

    {:ok, [{_, xml}]} = :zip.extract(String.to_charlist(path), [:memory, {:file_list, [~c"ComicInfo.xml"]}])
    assert ComicInfo.detect_version(xml) == "2.1"
  end

  # A CBZ whose entries are dated `age_s` seconds ago.
  defp aged_cbz(tmp, name, entries, age_s) do
    src = Path.join(tmp, "src_#{System.unique_integer([:positive])}")
    File.mkdir_p!(src)
    old = System.os_time(:second) - age_s

    for {file, data} <- entries do
      File.write!(Path.join(src, file), data)
      File.touch!(Path.join(src, file), old)
    end

    path = Path.join(tmp, name)
    names = Enum.map(entries, fn {file, _} -> String.to_charlist(file) end)
    {:ok, _} = :zip.create(String.to_charlist(path), names, cwd: String.to_charlist(src))
    path
  end

  defp entry(path, name) do
    {:ok, [{_, data}]} = :zip.extract(String.to_charlist(path), [:memory, {:file_list, [String.to_charlist(name)]}])
    data
  end

  @tagged_comicinfo """
  <ComicInfo><Title>Old</Title><Teams>Bat-family</Teams>
  <Pages><Page Image="0" Type="FrontCover" /><Page Image="1" DoublePage="true" /></Pages></ComicInfo>
  """

  test "ComicInfo <Pages> survive a rewrite", %{tmp: tmp, book: book} do
    path = aged_cbz(tmp, "Batman 001.cbz", [{"001.jpg", "p"}, {"ComicInfo.xml", @tagged_comicinfo}], 0)
    assert :ok = FileWriter.write_file(book, add_file(book, path, :cbz), %{"write_comicinfo" => true})

    xml = entry(path, "ComicInfo.xml")
    assert xml =~ ~s(<Page Image="0" Type="FrontCover" />)
    assert xml =~ ~s(<Page Image="1" DoublePage="true" />)
    assert xml =~ "<Title>I Am Gotham, Part One</Title>"
  end

  test "an existing ComicInfo.xml is updated even with ComicInfo write-back off", %{tmp: tmp, book: book} do
    path = aged_cbz(tmp, "Batman 001.cbz", [{"001.jpg", "p"}, {"ComicInfo.xml", @tagged_comicinfo}], 3600)
    assert :ok = FileWriter.write_file(book, add_file(book, path, :cbz), %{"write_comicinfo" => false})

    xml = entry(path, "ComicInfo.xml")
    assert xml =~ "<Title>I Am Gotham, Part One</Title>"
    assert xml =~ ~s(<Page Image="0" Type="FrontCover" />)
    refute xml =~ "Bat-family"
  end

  test "ComicInfo write-back off adds no ComicInfo.xml where there was none", %{tmp: tmp, book: book} do
    path = cbz_fixture(Path.join(tmp, "Batman 001.cbz"), [])
    assert :ok = FileWriter.write_file(book, add_file(book, path, :cbz), %{"write_comicinfo" => false})

    {:ok, [_ | entries]} = :zip.list_dir(String.to_charlist(path))
    refute Enum.any?(entries, &(elem(&1, 1) == ~c"ComicInfo.xml"))
  end

  test "a ComicInfo.xml older than the MetronInfo.xml beside it is ignored", %{tmp: tmp, book: book} do
    metron = book |> Record.from_book() |> MetronInfo.build()
    path = aged_cbz(tmp, "Batman 001.cbz", [{"001.jpg", "p"}, {"ComicInfo.xml", @tagged_comicinfo}], 3600)

    # Add a fresh MetronInfo.xml next to the hour-old ComicInfo.xml, as an external tagger would.
    {:ok, entries} = :zip.extract(String.to_charlist(path), [:memory])
    src = Path.join(tmp, "retag")
    File.mkdir_p!(src)
    old = System.os_time(:second) - 3600

    for {name, data} <- entries do
      File.write!(Path.join(src, to_string(name)), data)
      File.touch!(Path.join(src, to_string(name)), old)
    end

    File.write!(Path.join(src, "MetronInfo.xml"), metron)
    names = [~c"001.jpg", ~c"ComicInfo.xml", ~c"MetronInfo.xml"]
    {:ok, _} = :zip.create(String.to_charlist(path), names, cwd: String.to_charlist(src))

    parsed = Parser.parse_comicinfo(path)
    assert parsed.title == "I Am Gotham, Part One"
    refute Map.has_key?(parsed, :teams), "a team only the stale ComicInfo lists must not come back"
  end

  test "a rewrite keeps each entry's timestamp", %{tmp: tmp, book: book} do
    path = aged_cbz(tmp, "Batman 001.cbz", [{"001.jpg", "p"}], 86_400)
    {:ok, [_ | [{:zip_file, _, before, _, _, _}]]} = :zip.list_dir(String.to_charlist(path))

    assert :ok = FileWriter.write_file(book, add_file(book, path, :cbz), %{"write_comicinfo" => false})

    {:ok, [_ | entries]} = :zip.list_dir(String.to_charlist(path))
    {:zip_file, _, info, _, _, _} = Enum.find(entries, &(elem(&1, 1) == ~c"001.jpg"))
    assert elem(info, 5) == elem(before, 5)
  end

  if System.find_executable("rar") do
    test "a .cbz that is really RAR gets a sidecar instead of an error", %{tmp: tmp, book: book} do
      File.write!(Path.join(tmp, "001.jpg"), "p")
      path = Path.join(tmp, "Batman 001.cbz")
      {_, 0} = System.cmd("rar", ["a", "-inul", "-ep", "--", path, "001.jpg"], cd: tmp)

      assert :ok = FileWriter.write_file(book, add_file(book, path, :cbz), %{"write_comicinfo" => true})
      assert File.read!(Path.join(tmp, "Batman 001.xml")) =~ "<MetronInfo"
    end
  end

  test "rejects archives with unsafe entry names", %{tmp: tmp} do
    path = Path.join(tmp, "evil.cbz")
    {:ok, _} = :zip.create(String.to_charlist(path), [{~c"../escape.jpg", "x"}])
    assert {:error, _} = FileWriter.write_cbz(path, "<MetronInfo/>", nil)
  end
end
