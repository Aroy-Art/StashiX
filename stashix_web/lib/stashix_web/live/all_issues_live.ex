defmodule StashixWeb.AllIssuesLive do
  use StashixWeb, :live_view

  alias Stashix.Library

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @page_size 48

  @sort_options [
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
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "All Issues",
       sort: "title_asc",
       library_id: nil,
       page: 1,
       books: [],
       total: 0,
       total_pages: 1,
       loading: true,
       sort_options: @sort_options
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = max(1, String.to_integer(params["page"] || "1"))
    sort = params["sort"] || socket.assigns.sort
    library_id = params["library"] || nil

    {:noreply,
     socket
     |> assign(page: page, sort: sort, library_id: library_id)
     |> load_issues(page)}
  end

  @impl true
  def handle_event("filter_library", %{"id" => id}, socket) do
    library_id = if id == "", do: nil, else: id
    {:noreply, push_patch(socket, to: build_path(1, socket.assigns.sort, library_id))}
  end

  def handle_event("sort", %{"value" => sort}, socket) do
    {:noreply, push_patch(socket, to: build_path(1, sort, socket.assigns.library_id))}
  end

  def handle_event("goto_page", %{"page" => p}, socket) do
    page = String.to_integer(p) |> max(1) |> min(socket.assigns.total_pages)

    {:noreply, push_patch(socket, to: build_path(page, socket.assigns.sort, socket.assigns.library_id))}
  end

  defp build_path(page, sort, library_id) do
    params = %{page: page, sort: sort}
    params = if library_id, do: Map.put(params, :library, library_id), else: params
    ~p"/issues?#{params}"
  end

  defp load_issues(socket, page) do
    opts = [
      access: socket.assigns.access,
      type: "issue",
      sort: socket.assigns.sort,
      library_id: socket.assigns.library_id,
      limit: @page_size,
      offset: (page - 1) * @page_size
    ]

    books = Library.list_all_issues(opts)
    total = Library.count_all_books(opts)
    total_pages = max(1, ceil(total / @page_size))
    user_id = socket.assigns.current_user.id
    progress_map = Library.progress_map(user_id, Enum.map(books, & &1.id))

    assign(socket,
      books: books,
      total: total,
      total_pages: total_pages,
      progress_map: progress_map,
      loading: false
    )
  end

  @impl true
  def handle_info({:cover_updated, _}, socket), do: {:noreply, socket}
  def handle_info({:scan_progress, _}, socket), do: {:noreply, socket}
  def handle_info({:book_added, _}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <% first = List.first(@books) %>
    <.page wide fade cover_src={first && ~p"/api/books/#{first.id}/cover?s=s"}>
      <.page_hero title="Issues" eyebrow="Browse" count={@total > 0 && @total}>
        <:meta>
          <span>
            <span class="text-white font-semibold">{@total}</span>
            {if @total == 1, do: "issue", else: "issues"}
          </span>
          <span :if={@total_pages > 1}>page {@page} of {@total_pages}</span>
        </:meta>
      </.page_hero>

      <.browse_toolbar
        libraries={@sidebar_libraries}
        library_id={@library_id}
        sort_options={@sort_options}
        sort={@sort}
      />

      <%= if @books != [] do %>
        <.pagination id="page-top" page={@page} total_pages={@total_pages} />
        <.cover_grid>
          <.book_card :for={book <- @books} book={book} read={@progress_map[book.id]} as={:issue} />
        </.cover_grid>
        <.pagination page={@page} total_pages={@total_pages} scroll_to="page-top" />
      <% end %>

      <.empty_state :if={!@loading && @books == []} ghost="0" title="No issues on this shelf">
        {if @library_id, do: "Nothing in this library yet. Try another one.", else: "Scan a library to fill it."}
      </.empty_state>
    </.page>
    """
  end
end
