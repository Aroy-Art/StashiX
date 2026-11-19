# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.OpdsController do
  @moduledoc """
  The OPDS 1.2 catalog, for reading apps (KOReader, Panels, Chunky, Moon+
  and the like), under `/opds/v1.2`. Clients sign in with an app password
  (`StashixWeb.Plugs.OpdsAuth`) and see what the user may read.

  Navigation feeds: the root, the libraries, one library, a list of series.
  Acquisition feeds (books): continue reading, recently added, a library's
  books, a series, search. Books link their files for download when the
  user may download them, and comics and scanned PDFs also stream page by
  page (OPDS-PSE) whether or not they may.
  """
  use StashixWeb, :controller

  alias Stashix.{Library, Repo}
  alias Stashix.Library.Access
  alias StashixWeb.Opds.Feed

  @per_page 50
  @base Feed.base()

  def root(conn, _params) do
    entries = [
      nav("continue", gettext("Continue reading"), "/continue", :acquisition, gettext("Books you have started")),
      nav("new", gettext("Recently added"), "/new", :acquisition, gettext("The newest books first")),
      nav("series", gettext("Series"), "/series", :navigation, gettext("Every series, A to Z")),
      nav("books", gettext("All books"), "/books", :acquisition, gettext("Every book, A to Z")),
      nav("libraries", gettext("Libraries"), "/libraries", :navigation, gettext("Browse one library"))
    ]

    send_feed(conn, %{
      id: "urn:stashix:root",
      title: "Stashix",
      self: @base <> "/catalog",
      kind: :navigation,
      entries: entries
    })
  end

  def libraries(conn, _params) do
    entries =
      for lib <- Library.list_libraries(conn.assigns.current_user) |> Enum.sort_by(&String.downcase(&1.name)) do
        nav("library:#{lib.id}", lib.name, "/libraries/#{lib.id}", :navigation, nil)
      end

    send_feed(conn, %{
      id: "urn:stashix:libraries",
      title: gettext("Libraries"),
      self: @base <> "/libraries",
      up: @base <> "/catalog",
      kind: :navigation,
      entries: entries
    })
  end

  def library(conn, %{"id" => id}) do
    lib = Library.get_readable_library!(conn.assigns.access, id)
    q = "?library=#{lib.id}"

    entries = [
      nav("new:#{lib.id}", gettext("Recently added"), "/new" <> q, :acquisition, nil),
      nav("series:#{lib.id}", gettext("Series"), "/series" <> q, :navigation, nil),
      nav("books:#{lib.id}", gettext("All books"), "/books" <> q, :acquisition, nil)
    ]

    send_feed(conn, %{
      id: "urn:stashix:library:#{lib.id}",
      title: lib.name,
      self: "#{@base}/libraries/#{lib.id}",
      up: @base <> "/libraries",
      kind: :navigation,
      entries: entries
    })
  end

  def series_index(conn, params) do
    access = conn.assigns.access
    library_id = library_param(access, params)
    page = page_param(params)
    opts = [access: access, library_id: library_id, sort: "title_asc"]
    series = Library.list_all_series(opts ++ [limit: @per_page, offset: (page - 1) * @per_page])
    path = "/series" <> library_query(library_id)

    entries =
      for s <- series do
        nav(
          "series:#{s.id}",
          s.name,
          "/series/#{s.id}",
          :acquisition,
          ngettext("1 book", "%{count} books", s.issue_count)
        )
      end

    send_feed(conn, %{
      id: "urn:stashix:series" <> library_query(library_id),
      title: gettext("Series"),
      self: @base <> path,
      up: up(library_id),
      kind: :navigation,
      page: %{page: page, per_page: @per_page, total: Library.count_all_series(opts), path: @base <> path},
      entries: entries
    })
  end

  def series(conn, %{"id" => id}) do
    access = conn.assigns.access
    series = Library.get_series!(access, id)
    books = Library.list_books(series.library_id, access: access, series_id: series.id, sort: "issue_asc", limit: 2000)

    send_books(conn, books, %{
      id: "urn:stashix:series:#{series.id}",
      title: series.name,
      self: "#{@base}/series/#{series.id}",
      up: @base <> "/series"
    })
  end

  def books(conn, params), do: book_list(conn, params, "/books", gettext("All books"), "title_asc")
  def new(conn, params), do: book_list(conn, params, "/new", gettext("Recently added"), "added_desc")

  def continue(conn, _params) do
    %{access: access, current_user: user} = conn.assigns
    books = access |> Library.in_progress_books(user.id, @per_page) |> Enum.map(& &1.book)

    send_books(conn, books, %{
      id: "urn:stashix:continue",
      title: gettext("Continue reading"),
      self: @base <> "/continue",
      up: @base <> "/catalog"
    })
  end

  def search(conn, params) do
    q = String.trim(params["q"] || "")
    books = if q == "", do: [], else: Library.search_books(q, access: conn.assigns.access, limit: 100)

    send_books(conn, books, %{
      id: "urn:stashix:search",
      title: gettext("Search: %{query}", query: q),
      self: "#{@base}/search?" <> URI.encode_query(q: q),
      up: @base <> "/catalog"
    })
  end

  def opensearch(conn, _params) do
    conn
    |> put_resp_content_type("application/opensearchdescription+xml")
    |> send_resp(200, Feed.opensearch())
  end

  # A paged list of books, of one library or all.
  defp book_list(conn, params, path, title, sort) do
    access = conn.assigns.access
    library_id = library_param(access, params)
    page = page_param(params)
    opts = [access: access, library_id: library_id, sort: sort]
    books = Library.list_all_books(opts ++ [limit: @per_page, offset: (page - 1) * @per_page])
    path = path <> library_query(library_id)

    send_books(conn, books, %{
      id: "urn:stashix:" <> String.trim_leading(path, "/"),
      title: title,
      self: @base <> path,
      up: up(library_id),
      page: %{page: page, per_page: @per_page, total: Library.count_all_books(opts), path: @base <> path}
    })
  end

  defp send_books(conn, books, feed) do
    %{access: access, current_user: user} = conn.assigns
    books = Repo.preload(books, [:series, :files, credits: :creator])
    pages = Library.current_pages(user.id, Enum.map(books, & &1.id))

    entries =
      for book <- books do
        Feed.book_entry(book,
          download?: Access.can_download?(access, book.library_id),
          stream?: streams?(book),
          last_read: pages[book.id]
        )
      end

    send_feed(conn, Map.merge(feed, %{kind: :acquisition, entries: entries}))
  end

  # Books read as page images stream through the page endpoint.
  defp streams?(book) do
    case Library.get_preferred_book_file(book) do
      nil -> false
      file -> Library.reader_kind(book, file) == :images
    end
  end

  defp send_feed(conn, feed) do
    conn
    |> put_resp_content_type(Feed.content_type(feed.kind))
    |> send_resp(200, Feed.render(feed))
  end

  defp nav(id, title, path, kind, content),
    do:
      Feed.navigation_entry(%{
        id: "urn:stashix:" <> id,
        title: title,
        href: @base <> path,
        kind: kind,
        content: content
      })

  # A `library` param the user can read, else nil (every library).
  defp library_param(access, %{"library" => id}) when is_binary(id) do
    with {:ok, id} <- Ecto.UUID.cast(id), true <- Access.can_read_library?(access, id), do: id, else: (_ -> nil)
  end

  defp library_param(_access, _params), do: nil

  defp library_query(nil), do: ""
  defp library_query(id), do: "?library=#{id}"

  defp up(nil), do: @base <> "/catalog"
  defp up(library_id), do: "#{@base}/libraries/#{library_id}"

  defp page_param(%{"page" => p}) do
    case Integer.parse(p) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp page_param(_params), do: 1
end
