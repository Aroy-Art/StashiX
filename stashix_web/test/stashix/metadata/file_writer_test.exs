defmodule Stashix.Metadata.FileWriterTest do
  use Stashix.DataCase, async: false

  import Stashix.MetadataFixtures

  alias Stashix.{Library, Repo}
  alias Stashix.Library.BookFile
  alias Stashix.Metadata.{Parser, Importer}
  alias Stashix.Metadata.Writer.{FileWriter, MetronInfoXml, ComicInfoXml}

  setup do
    tmp = Path.join(System.tmp_dir!(), "stashix_writer_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    lib = library_fixture(tmp)
    series = series_fixture(lib, %{format: :"Single Issue", volume: 3})
    book = book_fixture(lib, series, %{summary: "A <b>bold</b> & brave tale", cover_date: ~D[2016-08-01], upc: "123"})

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
    xml = MetronInfoXml.build(book)
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

  test "ComicInfo compat copy maps credits to fields", %{book: book} do
    xml = ComicInfoXml.build(book)
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

  test "rejects archives with unsafe entry names", %{tmp: tmp} do
    path = Path.join(tmp, "evil.cbz")
    {:ok, _} = :zip.create(String.to_charlist(path), [{~c"../escape.jpg", "x"}])
    assert {:error, _} = FileWriter.write_cbz(path, "<MetronInfo/>", nil)
  end
end
