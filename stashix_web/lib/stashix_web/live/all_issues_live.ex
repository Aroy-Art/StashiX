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

  def handle_info({:cover_updated, _}, socket), do: {:noreply, socket}
  def handle_info({:scan_progress, _}, socket), do: {:noreply, socket}
  def handle_info({:book_added, _}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.browse_header title="Issues" subtitle={"#{@total} issues"}>
        <:controls>
          <.library_filter libraries={@sidebar_libraries} selected_id={@library_id} />
          <.separator orientation="vertical" class="h-5 mx-1" />
          <.sort_select options={@sort_options} selected={@sort} />
        </:controls>
      </.browse_header>

      <%= if @books != [] do %>
        <.pagination id="page-top" page={@page} total_pages={@total_pages} />
        <.media_grid>
          <%= for book <- @books do %>
            <% prog = @progress_map[book.id] %>
            <% progress =
              if prog && book.page_count && book.page_count > 1,
                do: prog / (book.page_count - 1),
                else: nil %>
            <.media_card
              navigate={~p"/book/#{book.id}"}
              title={if book.issue_number, do: "##{book.issue_number} – #{book.title}", else: book.title}
              cover_url={~p"/api/books/#{book.id}/cover"}
              size="m"
              subtitle={
                cond do
                  book.series -> book.series.name
                  book.year -> to_string(book.year)
                  true -> nil
                end
              }
              badge={
                cond do
                  book.volume && book.issue_number -> "Vol #{book.volume}  ##{book.issue_number}"
                  book.issue_number -> "##{book.issue_number}"
                  true -> nil
                end
              }
              progress={progress}
              type={:book}
              blurhash={book.cover && book.cover.blurhash}
            />
          <% end %>
        </.media_grid>
        <.pagination page={@page} total_pages={@total_pages} scroll_to="page-top" />
      <% end %>

      <%= if !@loading && @books == [] do %>
        <.browse_empty icon="lucide-layers" label="No issues found." />
      <% end %>
    </div>
    """
  end
end
