# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Calibre.Mapper do
  @moduledoc """
  Turns a book read by `Stashix.Calibre.Reader` into what Stashix stores
  (field mapping table in docs/calibre-plan.md):

      %{
        calibre_id: 12,
        calibre_uuid: "…",
        book: %{title, sort_title, type, issue_number, year, cover_date, added_at,
                language, summary, isbn, rating, calibre_modified_at},
        series: %{calibre_id, name, sort_name} | nil,
        record: %{publisher, tags, credits, external_ids, urls},   # `Stashix.Metadata.Record` keys
        creators: [%{name, sort_name}],
        files: [%{path, format, size}],       # paths relative to the library root
        skipped_formats: ["KEPUB", …],        # formats Stashix doesn't read
        cover: "Author/Title (12)/cover.jpg" | nil,
        fingerprint: "…"
      }

  The fingerprint hashes everything above except itself, so a sync only
  rewrites a book whose mapped values changed (D5).
  """

  @doc "Maps one Calibre book."
  def map_book(book) do
    series = book.series && %{calibre_id: book.series.id, name: book.series.name, sort_name: blank(book.series.sort)}
    {files, skipped} = files(book)
    cover_date = date(book.pubdate)

    mapped = %{
      calibre_id: book.id,
      calibre_uuid: book.uuid,
      book: %{
        title: book.title,
        sort_title: blank(book.sort),
        type: if(series, do: "issue", else: "standalone"),
        issue_number: if(series, do: decimal(book.series_index)),
        year: cover_date && cover_date.year,
        cover_date: cover_date,
        added_at: datetime(book.timestamp),
        language: language(List.first(book.languages)),
        summary: html_to_text(book.comments),
        isbn: blank(book.identifiers["isbn"]),
        rating: rating(book.rating),
        calibre_modified_at: datetime(book.last_modified)
      },
      series: series,
      record: %{
        publisher: book.publisher,
        tags: book.tags,
        credits: Enum.map(book.authors, &%{creator: &1.name, roles: ["Writer"]}),
        external_ids: external_ids(book.identifiers),
        urls: urls(book.identifiers)
      },
      creators: Enum.map(book.authors, &%{name: &1.name, sort_name: blank(&1.sort)}),
      files: files,
      skipped_formats: skipped,
      cover: if(book.has_cover, do: Path.join(book.path, "cover.jpg"))
    }

    Map.put(mapped, :fingerprint, fingerprint(mapped))
  end

  @doc "Hash of a mapped book (without its `:fingerprint`)."
  def fingerprint(mapped) do
    mapped
    |> Map.delete(:fingerprint)
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp files(book) do
    book.formats
    |> Enum.map(fn %{format: format, name: name, size: size} ->
      path = Path.join(book.path, "#{name}.#{String.downcase(format)}")
      {format, %{path: path, format: Stashix.Media.Formats.format(path), size: size}}
    end)
    |> Enum.split_with(fn {_, file} -> file.format end)
    |> then(fn {ok, skipped} -> {Enum.map(ok, &elem(&1, 1)), Enum.map(skipped, &elem(&1, 0))} end)
  end

  # Identifier types Calibre's metadata sources write, by Stashix source.
  @sources %{
    "google" => "Google Books",
    "amazon" => "Amazon",
    "mobi-asin" => "Amazon",
    "asin" => "Amazon",
    "goodreads" => "Goodreads",
    "openlibrary" => "Open Library",
    "issn" => "ISSN",
    "doi" => "DOI"
  }

  @doc "Stashix external id sources Calibre identifiers map to."
  def sources, do: @sources |> Map.values() |> Enum.uniq() |> Enum.sort()

  @doc "The Stashix external id source for a Calibre identifier type (`\"google\"` → `\"Google Books\"`), or nil."
  def source(type) when is_binary(type), do: @sources[String.downcase(type)]
  def source(_type), do: nil

  # `amazon` wins over `mobi-asin` for Amazon: it's what Calibre's own Amazon
  # source writes; `mobi-asin` comes from the file.
  defp external_ids(identifiers) do
    identifiers
    |> Enum.filter(fn {type, value} -> Map.has_key?(@sources, type) and blank(value) end)
    |> Enum.sort_by(fn {type, _} -> {type != "amazon", type} end)
    |> Enum.map(fn {type, value} -> %{source: @sources[type], source_id: value, is_primary: false} end)
    |> Enum.uniq_by(& &1.source)
  end

  # Calibre keeps plain links as `uri:` / `url:` identifiers.
  defp urls(identifiers) do
    for {type, value} <- Enum.sort(identifiers),
        type in ["uri", "url"],
        Stashix.Metadata.Importer.web_url?(value),
        do: %{url: value, is_primary: false}
  end

  # Calibre stores 0–10 (half stars); 0 means unrated.
  defp rating(n) when is_integer(n) and n > 0, do: min(n, 10) / 2
  defp rating(_), do: nil

  defp decimal(n) when is_float(n), do: n |> Decimal.from_float() |> Decimal.normalize()
  defp decimal(n) when is_integer(n), do: Decimal.new(n)
  defp decimal(_), do: nil

  # Calibre's text timestamps: "2024-01-02 03:04:05.123456+00:00". Year 101
  # ("0101-01-01") is its "unknown".
  defp datetime(text) when is_binary(text) do
    case DateTime.from_iso8601(String.replace(text, " ", "T", global: false)) do
      {:ok, %DateTime{year: year} = dt, _} when year > 101 ->
        dt |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)

      _ ->
        nil
    end
  end

  defp datetime(_), do: nil

  defp date(text), do: text |> datetime() |> then(&(&1 && NaiveDateTime.to_date(&1)))

  @doc """
  ISO 639-1 for Calibre's ISO 639-2 codes where one exists (`"eng"` →
  `"en"`); other codes stay as they are.
  """
  def language(nil), do: nil
  def language(code), do: Map.get(iso639(), String.downcase(code), code)

  # 639-2 (terminology and bibliographic) → 639-1, for the languages Stashix
  # names (`Stashix.Formatters.language_name/1`).
  defp iso639 do
    %{
      "afr" => "af",
      "ara" => "ar",
      "aze" => "az",
      "bel" => "be",
      "bul" => "bg",
      "ben" => "bn",
      "bos" => "bs",
      "cat" => "ca",
      "ces" => "cs",
      "cze" => "cs",
      "cym" => "cy",
      "wel" => "cy",
      "dan" => "da",
      "deu" => "de",
      "ger" => "de",
      "ell" => "el",
      "gre" => "el",
      "eng" => "en",
      "epo" => "eo",
      "spa" => "es",
      "est" => "et",
      "eus" => "eu",
      "baq" => "eu",
      "fas" => "fa",
      "per" => "fa",
      "fin" => "fi",
      "fra" => "fr",
      "fre" => "fr",
      "gle" => "ga",
      "glg" => "gl",
      "guj" => "gu",
      "heb" => "he",
      "hin" => "hi",
      "hrv" => "hr",
      "hun" => "hu",
      "hye" => "hy",
      "arm" => "hy",
      "ind" => "id",
      "isl" => "is",
      "ice" => "is",
      "ita" => "it",
      "jpn" => "ja",
      "kat" => "ka",
      "geo" => "ka",
      "kaz" => "kk",
      "khm" => "km",
      "kor" => "ko",
      "lit" => "lt",
      "lav" => "lv",
      "mkd" => "mk",
      "mac" => "mk",
      "mal" => "ml",
      "mon" => "mn",
      "mar" => "mr",
      "msa" => "ms",
      "may" => "ms",
      "mya" => "my",
      "bur" => "my",
      "nob" => "nb",
      "nld" => "nl",
      "dut" => "nl",
      "nor" => "no",
      "pan" => "pa",
      "pol" => "pl",
      "por" => "pt",
      "ron" => "ro",
      "rum" => "ro",
      "rus" => "ru",
      "slk" => "sk",
      "slo" => "sk",
      "slv" => "sl",
      "sqi" => "sq",
      "alb" => "sq",
      "srp" => "sr",
      "swe" => "sv",
      "swa" => "sw",
      "tam" => "ta",
      "tel" => "te",
      "tha" => "th",
      "tgl" => "tl",
      "fil" => "tl",
      "tur" => "tr",
      "ukr" => "uk",
      "urd" => "ur",
      "uzb" => "uz",
      "vie" => "vi",
      "zho" => "zh",
      "chi" => "zh",
      "zul" => "zu"
    }
  end

  @block ~w(p div br li h1 h2 h3 h4 h5 h6 blockquote tr pre ul ol table section article header footer hr)

  @doc """
  Calibre's HTML comments as the plain text book pages show
  (`whitespace-pre-line`): block elements become line breaks, paragraphs
  are separated by a blank line, everything else is text. Nothing of the
  HTML survives, so nothing in it can run.
  """
  def html_to_text(nil), do: nil

  def html_to_text(html) do
    case Floki.parse_fragment(html) do
      {:ok, nodes} ->
        nodes
        |> text()
        |> IO.iodata_to_binary()
        |> String.replace(" ", " ")
        |> String.split("\n")
        |> Enum.map(&(&1 |> String.replace(~r/[ \t\r]+/, " ") |> String.trim()))
        |> Enum.chunk_by(&(&1 == ""))
        |> Enum.reject(&(hd(&1) == ""))
        |> Enum.map_join("\n\n", &Enum.join(&1, "\n"))
        |> blank()

      _ ->
        blank(html)
    end
  end

  defp text(nodes) when is_list(nodes), do: Enum.map(nodes, &text/1)
  defp text(text) when is_binary(text), do: String.replace(text, ~r/\s+/, " ")
  defp text({"br", _, _}), do: "\n"
  defp text({tag, _, _}) when tag in ["script", "style"], do: []

  defp text({tag, _, children}) when tag in ["p", "div", "blockquote", "pre", "section", "article"],
    do: ["\n\n", text(children), "\n\n"]

  # Items end their line, so a list's items don't get blank lines between them.
  defp text({tag, _, children}) when tag in ["li", "tr"], do: [text(children), "\n"]
  defp text({tag, _, children}) when tag in @block, do: ["\n", text(children), "\n"]
  defp text({_tag, _, children}), do: text(children)
  defp text(_comment), do: []

  defp blank(nil), do: nil

  defp blank(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
