defmodule StashixWeb.PublisherLive do
  use StashixWeb, :live_view

  import StashixWeb.CollectionComponents

  alias Stashix.Library

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @page_size 48

  @series_sort_options [
    {"A → Z", "title_asc"},
    {"Z → A", "title_desc"},
    {"Year ↑", "year_asc"},
    {"Year ↓", "year_desc"},
    {"Date Added ↓", "added_desc"},
    {"Date Added ↑", "added_asc"}
  ]

  @books_sort_options [
    {"A → Z", "title_asc"},
    {"Z → A", "title_desc"},
    {"Year ↑", "year_asc"},
    {"Year ↓", "year_desc"},
    {"Date Added ↓", "added_desc"},
    {"Date Added ↑", "added_asc"}
  ]

  @issues_sort_options [
    {"A → Z", "title_asc"},
    {"Z → A", "title_desc"},
    {"Issue # ↑", "issue_asc"},
    {"Issue # ↓", "issue_desc"},
    {"Year ↑", "year_asc"},
    {"Year ↓", "year_desc"},
    {"Date Added ↓", "added_desc"},
    {"Date Added ↑", "added_asc"}
  ]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    publisher = Library.get_publisher_with_aliases!(socket.assigns.access, id)

    if publisher.canonical_publisher_id do
      {:ok, push_navigate(socket, to: ~p"/publisher/#{publisher.canonical_publisher_id}")}
    else
      access = socket.assigns.access
      series_count = Library.count_publisher_series(access, id)
      books_count = Library.count_publisher_books(access, id, "standalone")
      issues_count = Library.count_publisher_books(access, id, "issue")

      {:ok,
       assign(socket,
         page_title: publisher.name,
         publisher: publisher,
         series_count: series_count,
         books_count: books_count,
         issues_count: issues_count,
         items: [],
         total: 0,
         total_pages: 1,
         page: 1,
         sort: "title_asc",
         sort_options: @series_sort_options,
         progress_map: %{},
         loading: true
       )}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = max(1, String.to_integer(params["page"] || "1"))
    sort = params["sort"] || "title_asc"
    pub_id = socket.assigns.publisher.id
    user_id = socket.assigns.current_user.id
    access = socket.assigns.access

    socket =
      case socket.assigns.live_action do
        :show ->
          recent_series = Library.list_publisher_series(pub_id, limit: 20, access: access)
          recent_books = Library.list_publisher_books(pub_id, type: "standalone", limit: 20, access: access)
          recent_issues = Library.list_publisher_books(pub_id, type: "issue", limit: 20, access: access)

          assign(socket,
            recent_series: recent_series,
            recent_books: recent_books,
            recent_issues: recent_issues,
            loading: false
          )

        :series ->
          opts = [sort: sort, limit: @page_size, offset: (page - 1) * @page_size]
          items = Library.list_publisher_series(pub_id, [access: access] ++ opts)
          total = socket.assigns.series_count

          assign(socket,
            items: items,
            total: total,
            total_pages: max(1, ceil(total / @page_size)),
            page: page,
            sort: sort,
            sort_options: @series_sort_options,
            progress_map: %{},
            loading: false
          )

        :books ->
          opts = [
            type: "standalone",
            sort: sort,
            limit: @page_size,
            offset: (page - 1) * @page_size
          ]

          items = Library.list_publisher_books(pub_id, [access: access] ++ opts)
          total = socket.assigns.books_count
          progress_map = Library.progress_map(user_id, Enum.map(items, & &1.id))

          assign(socket,
            items: items,
            total: total,
            total_pages: max(1, ceil(total / @page_size)),
            page: page,
            sort: sort,
            sort_options: @books_sort_options,
            progress_map: progress_map,
            loading: false
          )

        :issues ->
          opts = [type: "issue", sort: sort, limit: @page_size, offset: (page - 1) * @page_size]
          items = Library.list_publisher_books(pub_id, [access: access] ++ opts)
          total = socket.assigns.issues_count
          progress_map = Library.progress_map(user_id, Enum.map(items, & &1.id))

          assign(socket,
            items: items,
            total: total,
            total_pages: max(1, ceil(total / @page_size)),
            page: page,
            sort: sort,
            sort_options: @issues_sort_options,
            progress_map: progress_map,
            loading: false
          )
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("sort", %{"value" => sort}, socket) do
    {:noreply, push_patch(socket, to: sub_path(socket, 1, sort))}
  end

  def handle_event("goto_page", %{"page" => p}, socket) do
    page = String.to_integer(p) |> max(1) |> min(socket.assigns.total_pages)
    {:noreply, push_patch(socket, to: sub_path(socket, page, socket.assigns.sort))}
  end

  defp sub_path(socket, page, sort) do
    id = socket.assigns.publisher.id
    params = %{page: page, sort: sort}

    case socket.assigns.live_action do
      :series -> ~p"/publisher/#{id}/series?#{params}"
      :books -> ~p"/publisher/#{id}/books?#{params}"
      :issues -> ~p"/publisher/#{id}/issues?#{params}"
      _ -> ~p"/publisher/#{id}"
    end
  end

  @impl true
  def handle_info({:cover_updated, _}, socket), do: {:noreply, socket}
  def handle_info({:scan_progress, _}, socket), do: {:noreply, socket}
  def handle_info({:book_added, _}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <.collection_page
      name={@publisher.name}
      kind="Publisher"
      base_path={~p"/publisher/#{@publisher.id}"}
      live_action={@live_action}
      series_count={assigns[:series_count] || 0}
      books_count={assigns[:books_count] || 0}
      issues_count={assigns[:issues_count] || 0}
      recent_series={assigns[:recent_series] || []}
      recent_books={assigns[:recent_books] || []}
      recent_issues={assigns[:recent_issues] || []}
      items={assigns[:items] || []}
      total={assigns[:total] || 0}
      page={assigns[:page] || 1}
      total_pages={assigns[:total_pages] || 1}
      sort_options={assigns[:sort_options] || []}
      sort={assigns[:sort]}
      progress_map={assigns[:progress_map] || %{}}
      loading={assigns[:loading] || false}
      empty_hint="No series or books are linked to it yet."
    >
      <:meta :if={@publisher.aliases != []}>
        <span>Also known as {Enum.map_join(@publisher.aliases, ", ", & &1.name)}</span>
      </:meta>
    </.collection_page>
    """
  end
end
