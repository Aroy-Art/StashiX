# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Calibre.MapperTest do
  use ExUnit.Case, async: true

  alias Stashix.Calibre.Mapper

  # A book as `Stashix.Calibre.Reader` returns it.
  defp book(attrs \\ %{}) do
    Map.merge(
      %{
        id: 12,
        uuid: "u-12",
        title: "Good Omens",
        sort: "Good Omens",
        path: "Terry Pratchett/Good Omens (12)",
        has_cover: true,
        timestamp: "2020-10-22 12:57:46.995333+00:00",
        pubdate: "1990-05-01 04:00:00+00:00",
        last_modified: "2023-02-03 10:39:10.271923+00:00",
        series_index: 1.0,
        author_sort: "Pratchett, Terry & Gaiman, Neil",
        authors: [
          %{id: 1, name: "Terry Pratchett", sort: "Pratchett, Terry", link: ""},
          %{id: 2, name: "Neil Gaiman", sort: "Gaiman, Neil", link: ""}
        ],
        series: nil,
        publisher: "Gollancz",
        tags: ["Comedy", "Fantasy"],
        languages: ["eng"],
        rating: 9,
        comments: nil,
        identifiers: %{},
        formats: [
          %{format: "EPUB", name: "Good Omens - Terry Pratchett", size: 10},
          %{format: "PDF", name: "Good Omens - Terry Pratchett", size: 20}
        ]
      },
      attrs
    )
  end

  test "maps the book's own fields" do
    m = Mapper.map_book(book())

    assert m.calibre_id == 12
    assert m.calibre_uuid == "u-12"

    assert m.book == %{
             title: "Good Omens",
             sort_title: "Good Omens",
             type: "standalone",
             issue_number: nil,
             year: 1990,
             cover_date: ~D[1990-05-01],
             added_at: ~N[2020-10-22 12:57:46],
             language: "en",
             summary: nil,
             isbn: nil,
             rating: 4.5,
             calibre_modified_at: ~N[2023-02-03 10:39:10]
           }

    assert m.series == nil
    assert m.cover == "Terry Pratchett/Good Omens (12)/cover.jpg"

    assert m.creators == [
             %{name: "Terry Pratchett", sort_name: "Pratchett, Terry"},
             %{name: "Neil Gaiman", sort_name: "Gaiman, Neil"}
           ]

    assert m.record.credits == [
             %{creator: "Terry Pratchett", roles: ["Writer"]},
             %{creator: "Neil Gaiman", roles: ["Writer"]}
           ]

    assert m.record.publisher == "Gollancz"
    assert m.record.tags == ["Comedy", "Fantasy"]
  end

  test "series and a fractional index" do
    m = Mapper.map_book(book(%{series: %{id: 5, name: "Omens", sort: "Omens"}, series_index: 2.5}))

    assert m.series == %{calibre_id: 5, name: "Omens", sort_name: "Omens"}
    assert m.book.type == "issue"
    assert Decimal.equal?(m.book.issue_number, Decimal.new("2.5"))

    assert Decimal.to_string(
             Mapper.map_book(book(%{series: m.series |> Map.put(:id, 5) |> Map.put(:sort, nil), series_index: 3.0})).book.issue_number
           ) == "3"
  end

  test "Calibre's unknown date and an unrated book" do
    m = Mapper.map_book(book(%{pubdate: "0101-01-01 00:00:00+00:00", rating: nil}))
    assert {m.book.cover_date, m.book.year, m.book.rating} == {nil, nil, nil}
    assert Mapper.map_book(book(%{rating: 0})).book.rating == nil
  end

  test "files, with formats Stashix can't read set aside" do
    m =
      Mapper.map_book(
        book(%{
          formats: [
            %{format: "EPUB", name: "Dune - Frank Herbert", size: 1},
            %{format: "KEPUB", name: "Dune - Frank Herbert", size: 2},
            %{format: "AZW3", name: "Dune - Frank Herbert", size: 3}
          ]
        })
      )

    assert m.files == [
             %{path: "Terry Pratchett/Good Omens (12)/Dune - Frank Herbert.epub", format: :epub, size: 1},
             %{path: "Terry Pratchett/Good Omens (12)/Dune - Frank Herbert.azw3", format: :azw3, size: 3}
           ]

    assert m.skipped_formats == ["KEPUB"]
  end

  test "identifiers" do
    m =
      Mapper.map_book(
        book(%{
          identifiers: %{
            "isbn" => "9780575048003",
            "google" => "abc",
            "mobi-asin" => "B000FILE",
            "amazon" => "B000STORE",
            "barnesnoble" => "w/1",
            "uri" => "https://example.com/good-omens",
            "url" => "javascript:alert(1)"
          }
        })
      )

    assert m.book.isbn == "9780575048003"

    assert Enum.sort_by(m.record.external_ids, & &1.source) == [
             %{source: "Amazon", source_id: "B000STORE", is_primary: false},
             %{source: "Google Books", source_id: "abc", is_primary: false}
           ]

    assert m.record.urls == [%{url: "https://example.com/good-omens", is_primary: false}]
  end

  test "every mapped source exists on book external ids" do
    values = Ecto.Enum.values(Stashix.Library.BookExternalId, :source) |> Enum.map(&to_string/1)
    assert Mapper.sources() -- values == []
  end

  test "languages" do
    assert Mapper.language("eng") == "en"
    assert Mapper.language("DEU") == "de"
    assert Mapper.language("ger") == "de"
    assert Mapper.language("tlh") == "tlh"
    assert Mapper.map_book(book(%{languages: []})).book.language == nil
    assert Mapper.map_book(book(%{languages: ["jpn", "eng"]})).book.language == "ja"
  end

  describe "html_to_text/1" do
    test "paragraphs and line breaks" do
      html = """
      <div><p><strong>From #1&nbsp;<em>New York Times</em> author</strong><br>
      second line</p>
      <p>Next   paragraph.</p><ul><li>one</li><li>two</li></ul></div>
      """

      assert Mapper.html_to_text(html) ==
               "From #1 New York Times author\nsecond line\n\nNext paragraph.\n\none\ntwo"
    end

    test "drops scripts and markup" do
      assert Mapper.html_to_text(~s|<p onclick="x()">Hi<script>alert(1)</script></p><style>p{}</style>|) == "Hi"
    end

    test "plain text and empty" do
      assert Mapper.html_to_text("Just text") == "Just text"
      assert Mapper.html_to_text("<p> </p>") == nil
      assert Mapper.html_to_text(nil) == nil
    end
  end

  describe "fingerprint" do
    test "stable for the same book, different when a mapped value changes" do
      a = Mapper.map_book(book())
      assert a.fingerprint == Mapper.map_book(book()).fingerprint
      refute a.fingerprint == Mapper.map_book(book(%{tags: ["Comedy"]})).fingerprint
      refute a.fingerprint == Mapper.map_book(book(%{authors: tl(book().authors)})).fingerprint
    end

    test "ignores what isn't mapped" do
      assert Mapper.map_book(book()).fingerprint == Mapper.map_book(book(%{author_sort: "x"})).fingerprint
    end
  end
end
