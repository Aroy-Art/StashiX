# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.Opds.Feed do
  @moduledoc """
  OPDS 1.2 (Atom) feeds as iodata.

  A feed is a map:

    * `:id`, `:title`, `:self` (its path), `:kind` (`:navigation` or
      `:acquisition`)
    * `:up` — the parent feed's path, optional
    * `:page` — `%{page, per_page, total, path}` for paged feeds; `path` is
      the feed's path without `page`
    * `:entries` — from `navigation_entry/1` or `book_entry/2`

  Every link is a path on this server: clients resolve them against the
  feed's address, which also keeps them right behind a reverse proxy.
  """

  @base "/opds/v1.2"

  @mime %{
    cbz: "application/vnd.comicbook+zip",
    cbr: "application/vnd.comicbook-rar",
    cb7: "application/x-cb7",
    epub: "application/epub+zip",
    pdf: "application/pdf",
    mobi: "application/x-mobipocket-ebook",
    azw3: "application/vnd.amazon.mobi8-ebook",
    azw: "application/vnd.amazon.ebook",
    fb2: "application/x-fictionbook+xml",
    fbz: "application/x-zip-compressed-fb2"
  }

  @author_roles [:Writer, :Script, :Story, :Plot]

  def base, do: @base

  @doc "The content type of a feed of `kind`."
  def content_type(:navigation), do: "application/atom+xml;profile=opds-catalog;kind=navigation"
  def content_type(:acquisition), do: "application/atom+xml;profile=opds-catalog;kind=acquisition"

  @doc "A feed, rendered."
  def render(feed) do
    [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<feed xmlns="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/terms/" ),
      ~s(xmlns:opds="http://opds-spec.org/2010/catalog" xmlns:opensearch="http://a9.com/-/spec/opensearch/1.1/" ),
      ~s(xmlns:pse="http://vaemendis.net/opds-pse/ns">\n),
      tag("id", feed.id),
      tag("title", feed.title),
      tag("updated", now()),
      "<author><name>Stashix</name></author>\n",
      link("self", feed.self, content_type(feed.kind)),
      link("start", @base <> "/catalog", content_type(:navigation)),
      if(feed[:up], do: link("up", feed.up, content_type(:navigation)), else: []),
      link("search", @base <> "/search.xml", "application/opensearchdescription+xml"),
      link("search", @base <> "/search?q={searchTerms}", "application/atom+xml"),
      pagination(feed[:page], feed.kind),
      feed.entries,
      "</feed>\n"
    ]
  end

  defp pagination(nil, _kind), do: []

  defp pagination(%{page: page, per_page: per, total: total, path: path}, kind) do
    last = max(1, ceil(total / per))
    type = content_type(kind)

    [
      tag("opensearch:totalResults", total),
      tag("opensearch:itemsPerPage", per),
      tag("opensearch:startIndex", (page - 1) * per + 1),
      if(page > 1,
        do: [link("first", page_path(path, 1), type), link("previous", page_path(path, page - 1), type)],
        else: []
      ),
      if(page < last,
        do: [link("next", page_path(path, page + 1), type), link("last", page_path(path, last), type)],
        else: []
      )
    ]
  end

  defp page_path(path, page), do: path <> if(String.contains?(path, "?"), do: "&", else: "?") <> "page=#{page}"

  @doc """
  An entry that leads to another feed: `%{id, title, href, kind, content}`
  (`content` optional, a line of text under the title).
  """
  def navigation_entry(entry) do
    [
      "<entry>\n",
      tag("id", entry.id),
      tag("title", entry.title),
      tag("updated", now()),
      if(entry[:content], do: ~s(<content type="text">#{esc(entry.content)}</content>\n), else: []),
      link("subsection", entry.href, content_type(entry[:kind] || :navigation)),
      "</entry>\n"
    ]
  end

  @doc """
  A book. `opts`:

    * `:download?` — whether the user may download its files (acquisition
      links, one per format)
    * `:stream?` — whether it reads as page images (an OPDS-PSE stream link)
    * `:last_read` — the page the user reached, for PSE clients

  The book needs `:series`, `:files` and `credits: :creator` loaded.
  """
  def book_entry(book, opts \\ []) do
    # Best format first: clients that offer one download take the first link.
    files =
      book.files
      |> Enum.filter(&is_nil(&1.deleted_at))
      |> Enum.sort_by(&Stashix.Media.Formats.reading_rank(&1.format))

    cover = "#{@base}/books/#{book.id}/cover"

    [
      "<entry>\n",
      tag("id", entry_id(book)),
      tag("title", entry_title(book)),
      tag("updated", timestamp(book.updated_at)),
      Enum.map(authors(book), &["<author>", tag("name", &1), "</author>\n"]),
      if(book.language, do: tag("dc:language", book.language), else: []),
      if(book.year, do: tag("dc:issued", book.year), else: []),
      if(book.isbn, do: tag("dc:identifier", "urn:isbn:" <> book.isbn), else: []),
      if(book.summary, do: ~s(<summary type="text">#{esc(book.summary)}</summary>\n), else: []),
      link("http://opds-spec.org/image", cover, "image/jpeg"),
      link("http://opds-spec.org/image/thumbnail", cover <> "?s=s", "image/jpeg"),
      if(opts[:download?], do: Enum.map(files, &acquisition_link(book, &1)), else: []),
      if(opts[:stream?] && book.page_count > 0, do: stream_link(book, opts[:last_read]), else: []),
      "</entry>\n"
    ]
  end

  # A Calibre book keeps the id Calibre's own OPDS feed gives it, so readers
  # (KOReader) that knew it from Calibre see the same book.
  defp entry_id(%{calibre_uuid: uuid}) when is_binary(uuid), do: "urn:uuid:" <> uuid
  defp entry_id(book), do: "urn:stashix:book:#{book.id}"

  defp acquisition_link(book, file) do
    ~s(<link rel="http://opds-spec.org/acquisition" type="#{Map.get(@mime, file.format, "application/octet-stream")}" ) <>
      ~s(href="#{@base}/books/#{book.id}/download?formats=#{file.format}" length="#{file.file_size}" ) <>
      ~s(title="#{esc(file.format |> to_string() |> String.upcase())}"/>\n)
  end

  # Pages from 0, as the page endpoint counts them; PSE counts from 0 too.
  defp stream_link(book, last_read) do
    last = if last_read, do: ~s( pse:lastRead="#{last_read}"), else: ""

    ~s(<link rel="http://vaemendis.net/opds-pse/stream" type="image/jpeg" ) <>
      ~s(href="#{@base}/books/#{book.id}/page/{pageNumber}?w={maxWidth}" pse:count="#{book.page_count}"#{last}/>\n)
  end

  @doc ~S'How a book is named in a list: "Saga #3 – Chapter Three" for an issue.'
  def entry_title(%{type: "issue", series: %{name: series}} = book) when is_binary(series) do
    case Stashix.Formatters.book_number_label(book) do
      nil -> book.title || series
      number when book.title in [nil, ""] -> "#{series} #{number}"
      number -> "#{series} #{number} – #{book.title}"
    end
  end

  def entry_title(book), do: book.title

  defp authors(%{credits: credits}) when is_list(credits) do
    credits
    |> Enum.filter(&(&1.role in @author_roles))
    |> Enum.map(& &1.creator.name)
    |> Enum.uniq()
  end

  defp authors(_book), do: []

  @doc "The OpenSearch description clients read to search the catalog."
  def opensearch do
    [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">\n),
      "<ShortName>Stashix</ShortName>\n",
      "<Description>Search the Stashix library</Description>\n",
      "<InputEncoding>UTF-8</InputEncoding>\n",
      "<OutputEncoding>UTF-8</OutputEncoding>\n",
      ~s(<Url type="#{content_type(:acquisition)}" template="#{@base}/search?q={searchTerms}"/>\n),
      "</OpenSearchDescription>\n"
    ]
  end

  defp link(rel, href, type), do: ~s(<link rel="#{rel}" href="#{esc(href)}" type="#{type}"/>\n)

  defp tag(name, value), do: ["<", name, ">", esc(to_string(value)), "</", name, ">\n"]

  defp esc(text), do: Plug.HTML.html_escape(text)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp timestamp(%NaiveDateTime{} = t),
    do: t |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601() |> Kernel.<>("Z")

  defp timestamp(%DateTime{} = t), do: t |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  defp timestamp(_), do: now()
end
