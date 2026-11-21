# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.Opds do
  @moduledoc """
  What the OPDS 1.2 (`StashixWeb.Opds.Feed`, Atom) and 2.0
  (`StashixWeb.Opds.Feed2`, JSON) catalogs share.

  `StashixWeb.OpdsController` builds each feed once, as a map that does not
  know its format, and the catalog's version picks the renderer:

    * `:id`, `:title`, `:self` (its path), `:kind` (`:navigation` or
      `:acquisition`)
    * `:up` — the parent feed's path, optional
    * `:page` — `%{page, per_page, total}` for paged feeds
    * `:entries` — `{:nav, %{id, title, href, kind, content}}` (another
      feed; `content` is a line of text or nil) or `{:book, book, opts}`

  Paths in a feed leave out the catalog's prefix (`/opds/v1.2`,
  `/opds/v2`); the renderer adds it. Links are paths on this server, so
  clients resolve them against the feed's address, which keeps them right
  behind a reverse proxy.

  Book `opts`:

    * `:download?` — the user may download its files (acquisition links)
    * `:stream?` — it reads as page images (OPDS-PSE in 1.2, a Divina
      manifest in 2.0)
    * `:last_read` — the page index the user reached
  """

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

  @doc "The Readium progression media type and link relation (OPDS 2 / Readium Progression API)."
  def progression_type, do: "application/vnd.readium.progression+json"
  def progression_rel, do: "http://www.cantook.com/api/progression"

  def mime(format), do: Map.get(@mime, format, "application/octet-stream")

  @doc """
  A book's files that are still on disk, best format first: clients that
  offer one download take the first link.
  """
  def files(book) do
    book.files
    |> Enum.filter(&is_nil(&1.deleted_at))
    |> Enum.sort_by(&Stashix.Media.Formats.reading_rank(&1.format))
  end

  @doc """
  A book's id in the feeds. A Calibre book keeps the id Calibre's own OPDS
  feed gives it, so readers (KOReader) that knew it from Calibre see the
  same book.
  """
  def entry_id(%{calibre_uuid: uuid}) when is_binary(uuid), do: "urn:uuid:" <> uuid
  def entry_id(book), do: "urn:stashix:book:#{book.id}"

  @doc ~S'How a book is named in a list: "Saga #3 – Chapter Three" for an issue.'
  def entry_title(%{type: "issue", series: %{name: series}} = book) when is_binary(series) do
    case Stashix.Formatters.book_number_label(book) do
      nil -> book.title || series
      number when book.title in [nil, ""] -> "#{series} #{number}"
      number -> "#{series} #{number} – #{book.title}"
    end
  end

  def entry_title(book), do: book.title

  @doc "Writers of a book (credits must be loaded)."
  def authors(%{credits: credits}) when is_list(credits) do
    credits
    |> Enum.filter(&(&1.role in @author_roles))
    |> Enum.map(& &1.creator.name)
    |> Enum.uniq()
  end

  def authors(_book), do: []

  @doc "Number of the last page of a paged feed."
  def last_page(%{per_page: per, total: total}), do: max(1, ceil(total / per))

  @doc "`path` with its `page` query parameter set."
  def page_path(path, page), do: path <> if(String.contains?(path, "?"), do: "&", else: "?") <> "page=#{page}"

  def timestamp(%NaiveDateTime{} = t),
    do: t |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601() |> Kernel.<>("Z")

  def timestamp(%DateTime{} = t), do: t |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  def timestamp(_), do: now()

  def now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
