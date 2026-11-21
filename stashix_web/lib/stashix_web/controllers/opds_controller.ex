# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.OpdsController do
  @moduledoc """
  The OPDS catalogs, for reading apps (KOReader, Panels, Chunky, Thorium,
  Moon+ and the like): OPDS 1.2 (Atom) under `/opds/v1.2`, OPDS 2.0 (JSON)
  under `/opds/v2`. Both serve the same feeds (see `StashixWeb.Opds`); the
  path picks the renderer. Clients sign in with an app password
  (`StashixWeb.Plugs.OpdsAuth`) and see what the user may read.

  Navigation feeds: the root, the libraries, one library, a list of series.
  Acquisition feeds (books): continue reading, recently added, a library's
  books, a series, search. Books link their files for download when the
  user may download them; comics and scanned PDFs also stream page by page
  (OPDS-PSE in 1.2, a Divina manifest in 2.0) whether or not they may.

  Reading progress goes both ways through the Readium Progression API
  (`progression/2`, `update_progression/2`), and through Komga's
  `PATCH /api/v1/books/:id/read-progress` (`read_progress/2`) for apps that
  speak that.
  """
  use StashixWeb, :controller

  alias Stashix.{Library, Repo}
  alias Stashix.Library.Access
  alias StashixWeb.Opds.{Feed, Feed2, Progression}

  @per_page 50

  def root(conn, _params) do
    entries = [
      nav("continue", gettext("Continue reading"), "/continue", :acquisition, gettext("Books you have started")),
      nav("new", gettext("Recently added"), "/new", :acquisition, gettext("The newest books first")),
      nav("series", gettext("Series"), "/series", :navigation, gettext("Every series, A to Z")),
      nav("books", gettext("All books"), "/books", :acquisition, gettext("Every book, A to Z")),
      nav("libraries", gettext("Libraries"), "/libraries", :navigation, gettext("Browse one library"))
    ]

    send_feed(conn, %{id: "urn:stashix:root", title: "Stashix", self: "/catalog", kind: :navigation, entries: entries})
  end

  def libraries(conn, _params) do
    entries =
      for lib <- Library.list_libraries(conn.assigns.current_user) |> Enum.sort_by(&String.downcase(&1.name)) do
        nav("library:#{lib.id}", lib.name, "/libraries/#{lib.id}", :navigation, nil)
      end

    send_feed(conn, %{
      id: "urn:stashix:libraries",
      title: gettext("Libraries"),
      self: "/libraries",
      up: "/catalog",
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
      self: "/libraries/#{lib.id}",
      up: "/libraries",
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
      self: "/series" <> library_query(library_id),
      up: up(library_id),
      kind: :navigation,
      page: %{page: page, per_page: @per_page, total: Library.count_all_series(opts)},
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
      self: "/series/#{series.id}",
      up: "/series"
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
      self: "/continue",
      up: "/catalog"
    })
  end

  # OPDS 1.2 clients fill in `q` (OpenSearch), OPDS 2.0 ones `query`.
  def search(conn, params) do
    q = String.trim(params["q"] || params["query"] || "")
    books = if q == "", do: [], else: Library.search_books(q, access: conn.assigns.access, limit: 100)

    send_books(conn, books, %{
      id: "urn:stashix:search",
      title: gettext("Search: %{query}", query: q),
      self: "/search?" <> URI.encode_query(q: q),
      up: "/catalog"
    })
  end

  def opensearch(conn, _params) do
    conn
    |> put_resp_content_type("application/opensearchdescription+xml")
    |> send_resp(200, Feed.opensearch())
  end

  ## OPDS 2.0 only

  def authentication(conn, _params) do
    conn
    |> put_resp_content_type("application/opds-authentication+json")
    |> send_resp(200, Jason.encode_to_iodata!(Feed2.authentication_document()))
  end

  def publication(conn, %{"id" => id}) do
    [entry] = conn |> book_entries([Library.get_book!(conn.assigns.access, id)])

    conn
    |> put_resp_content_type(Feed2.publication_type())
    |> send_resp(200, Jason.encode_to_iodata!(Feed2.publication(entry)))
  end

  def manifest(conn, %{"id" => id}) do
    book = conn.assigns.access |> Library.get_book!(id) |> Repo.preload([:series, :files, credits: :creator])

    if Progression.mode(book) == :images and book.page_count > 0 do
      conn
      |> put_resp_content_type(Feed2.divina_type())
      |> send_resp(200, Jason.encode_to_iodata!(Feed2.manifest(book)))
    else
      conn |> put_status(:not_found) |> json(%{error: "not a comic"})
    end
  end

  ## Progress

  @doc "Readium Progression API: where the user is in the book (204 if never opened)."
  def progression(conn, %{"id" => id}) do
    book = progress_book(conn, id)

    case Library.get_progress(conn.assigns.current_user.id, book.id) do
      nil ->
        send_resp(conn, 204, "")

      progress ->
        conn
        |> put_resp_content_type(StashixWeb.Opds.progression_type())
        |> send_resp(200, Jason.encode_to_iodata!(Progression.to_json(progress, book)))
    end
  end

  @doc "Readium Progression API: saves where the user is; 409 if the server knows a newer spot."
  def update_progression(conn, %{"id" => id} = params) do
    %{access: access, current_user: user} = conn.assigns
    book = progress_book(conn, id)
    saved = Library.get_progress(user.id, book.id)

    with false <- Progression.stale?(params, saved),
         {:ok, page, opts} <- Progression.from_json(params, book, saved),
         {:ok, _} <- Library.update_progress(access, user.id, book.id, page, opts) do
      send_resp(conn, 204, "")
    else
      true -> conn |> put_status(:conflict) |> json(%{error: "a newer progression is saved"})
      {:error, reason} when is_binary(reason) -> conn |> put_status(:bad_request) |> json(%{error: reason})
      _ -> conn |> put_status(:bad_request) |> json(%{error: "invalid progression"})
    end
  end

  @doc """
  Komga's read-progress call (`{"page": n, "completed": bool}`, pages from
  1), which some reading apps send as you read.
  """
  def read_progress(conn, %{"id" => id} = params) do
    %{access: access, current_user: user} = conn.assigns
    book = progress_book(conn, id)
    last = max(book.page_count - 1, 0)

    result =
      cond do
        params["completed"] == true -> {:ok, last, [progression: 1.0]}
        is_integer(params["page"]) and params["page"] in 1..(last + 1) -> {:ok, params["page"] - 1, []}
        true -> :error
      end

    with {:ok, page, opts} <- result,
         {:ok, _} <- Library.update_progress(access, user.id, book.id, page, opts) do
      send_resp(conn, 204, "")
    else
      _ -> conn |> put_status(:bad_request) |> json(%{error: "page must be within 1 and the page count"})
    end
  end

  defp progress_book(conn, id), do: conn.assigns.access |> Library.get_book!(id) |> Repo.preload(:files)

  ## Feeds

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
      self: path,
      up: up(library_id),
      page: %{page: page, per_page: @per_page, total: Library.count_all_books(opts)}
    })
  end

  defp send_books(conn, books, feed),
    do: send_feed(conn, Map.merge(feed, %{kind: :acquisition, entries: book_entries(conn, books)}))

  defp book_entries(conn, books) do
    %{access: access, current_user: user} = conn.assigns
    books = Repo.preload(books, [:series, :files, credits: :creator])
    pages = Library.current_pages(user.id, Enum.map(books, & &1.id))

    for book <- books do
      {:book, book,
       [
         download?: Access.can_download?(access, book.library_id),
         stream?: Progression.mode(book) == :images,
         last_read: pages[book.id]
       ]}
    end
  end

  defp send_feed(conn, feed) do
    renderer = renderer(conn)

    conn
    |> put_resp_content_type(renderer.content_type(feed.kind))
    |> send_resp(200, renderer.render(feed))
  end

  defp renderer(%{path_info: ["opds", "v2" | _]}), do: Feed2
  defp renderer(_conn), do: Feed

  defp nav(id, title, path, kind, content),
    do: {:nav, %{id: "urn:stashix:" <> id, title: title, href: path, kind: kind, content: content}}

  # A `library` param the user can read, else nil (every library).
  defp library_param(access, %{"library" => id}) when is_binary(id) do
    with {:ok, id} <- Ecto.UUID.cast(id), true <- Access.can_read_library?(access, id), do: id, else: (_ -> nil)
  end

  defp library_param(_access, _params), do: nil

  defp library_query(nil), do: ""
  defp library_query(id), do: "?library=#{id}"

  defp up(nil), do: "/catalog"
  defp up(library_id), do: "/libraries/#{library_id}"

  defp page_param(%{"page" => p}) do
    case Integer.parse(p) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp page_param(_params), do: 1
end
