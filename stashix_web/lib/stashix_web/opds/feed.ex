# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.Opds.Feed do
  @moduledoc """
  OPDS 1.2 (Atom) rendering of the feeds described in `StashixWeb.Opds`,
  as iodata, under `/opds/v1.2`. Comics stream through OPDS-PSE.
  """

  import StashixWeb.Opds

  @base "/opds/v1.2"

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
      link("self", @base <> feed.self, content_type(feed.kind)),
      link("start", @base <> "/catalog", content_type(:navigation)),
      if(feed[:up], do: link("up", @base <> feed.up, content_type(:navigation)), else: []),
      link("search", @base <> "/search.xml", "application/opensearchdescription+xml"),
      link("search", @base <> "/search?q={searchTerms}", "application/atom+xml"),
      pagination(feed),
      Enum.map(feed.entries, &entry/1),
      "</feed>\n"
    ]
  end

  defp pagination(%{page: %{page: page, per_page: per, total: total} = paging, self: self, kind: kind}) do
    last = last_page(paging)
    type = content_type(kind)
    path = @base <> self

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

  defp pagination(_feed), do: []

  defp entry({:nav, entry}) do
    [
      "<entry>\n",
      tag("id", entry.id),
      tag("title", entry.title),
      tag("updated", now()),
      if(entry[:content], do: ~s(<content type="text">#{esc(entry.content)}</content>\n), else: []),
      link("subsection", @base <> entry.href, content_type(entry[:kind] || :navigation)),
      "</entry>\n"
    ]
  end

  defp entry({:book, book, opts}) do
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
      if(opts[:download?], do: Enum.map(files(book), &acquisition_link(book, &1)), else: []),
      if(opts[:stream?] && book.page_count > 0, do: stream_link(book, opts[:last_read]), else: []),
      link(progression_rel(), "#{@base}/books/#{book.id}/progression", progression_type()),
      "</entry>\n"
    ]
  end

  defp acquisition_link(book, file) do
    ~s(<link rel="http://opds-spec.org/acquisition" type="#{mime(file.format)}" ) <>
      ~s(href="#{@base}/books/#{book.id}/download?formats=#{file.format}" length="#{file.file_size}" ) <>
      ~s(title="#{esc(file.format |> to_string() |> String.upcase())}"/>\n)
  end

  # Pages from 0, as the page endpoint counts them; PSE counts from 0 too.
  defp stream_link(book, last_read) do
    last = if last_read, do: ~s( pse:lastRead="#{last_read}"), else: ""

    ~s(<link rel="http://vaemendis.net/opds-pse/stream" type="image/jpeg" ) <>
      ~s(href="#{@base}/books/#{book.id}/page/{pageNumber}?w={maxWidth}" pse:count="#{book.page_count}"#{last}/>\n)
  end

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
end
