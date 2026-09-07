defmodule StashixWeb.LibraryLive do
  use StashixWeb, :live_view

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
  def mount(%{"id" => library_id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Stashix.PubSub, "scan:#{library_id}")
    end

    library = Library.get_library!(library_id)
    series_count = Library.count_series(library_id)
    books_count = Library.count_books(library_id)
    issues_count = Library.count_issues(library_id)

    {:ok,
     assign(socket,
       page_title: library.name,
       library: library,
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

  @impl true
  def handle_params(params, _uri, socket) do
    page = max(1, String.to_integer(params["page"] || "1"))
    sort = params["sort"] || "title_asc"
    lib_id = socket.assigns.library.id
    user_id = socket.assigns.current_user.id

    socket =
      case socket.assigns.live_action do
        :show ->
          recent_series = Library.list_series(lib_id, limit: 20, sort: "added_desc")
          recent_books = Library.list_books(lib_id, type: "standalone", limit: 20, sort: "added_desc")
          recent_issues = Library.list_books(lib_id, type: "issue", limit: 20, sort: "added_desc")

          assign(socket,
            recent_series: recent_series,
            recent_books: recent_books,
            recent_issues: recent_issues,
            loading: false
          )

        :series ->
          opts = [sort: sort, limit: @page_size, offset: (page - 1) * @page_size]
          items = Library.list_series(lib_id, opts)
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
          opts = [type: "standalone", sort: sort, limit: @page_size, offset: (page - 1) * @page_size]
          items = Library.list_books(lib_id, opts)
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
          items = Library.list_books(lib_id, opts)
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

  @impl true
  def handle_info({:scan_progress, _progress}, socket), do: {:noreply, socket}

  def handle_info({:book_added, _book}, socket) do
    {:noreply, push_patch(socket, to: sub_path(socket, 1, socket.assigns.sort))}
  end

  defp sub_path(socket, page, sort) do
    id = socket.assigns.library.id
    params = %{page: page, sort: sort}

    case socket.assigns.live_action do
      :series -> ~p"/library/#{id}/series?#{params}"
      :books -> ~p"/library/#{id}/books?#{params}"
      :issues -> ~p"/library/#{id}/issues?#{params}"
      _ -> ~p"/library/#{id}"
    end
  end

  defp section_label(:series), do: "Series"
  defp section_label(:books), do: "Books"
  defp section_label(:issues), do: "Issues"

  defp series_date_range(%{start_year: nil}), do: nil
  defp series_date_range(%{start_year: y, end_year: nil, ongoing: true}), do: "#{y}–"
  defp series_date_range(%{start_year: y, end_year: nil}), do: to_string(y)
  defp series_date_range(%{start_year: y, end_year: y}), do: to_string(y)
  defp series_date_range(%{start_year: s, end_year: e}), do: "#{s}–#{e}"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Breadcrumb --%>
      <div class="flex flex-wrap items-center gap-x-2 gap-y-3 text-sm">
        <button onclick="history.back()" class="flex items-center gap-1 px-2.5 py-1 rounded-md border border-white/20 text-gray-300 hover:border-white/40 hover:text-white transition-colors flex-shrink-0">
          <.icon name="lucide-chevron-left" class="w-4 h-4" />
          Back
        </button>
        <div class="flex items-center gap-2 w-full sm:w-auto sm:flex-1 min-w-0 overflow-hidden order-first sm:order-none">
          <a href="/" class="text-gray-500 hover:text-gray-300 flex-shrink-0">Home</a>
          <span class="text-gray-700 flex-shrink-0">/</span>
          <%= if @live_action != :show do %>
            <a href={~p"/library/#{@library.id}"} class="text-gray-500 hover:text-gray-300 flex-shrink-0">{@library.name}</a>
            <span class="text-gray-700 flex-shrink-0">/</span>
            <span class="text-gray-300 truncate min-w-0">{section_label(@live_action)}</span>
          <% else %>
            <span class="text-gray-300 truncate min-w-0">{@library.name}</span>
          <% end %>
        </div>
      </div>

      <%= if @live_action == :show do %>
        <%!-- Overview --%>
        <div>
          <h1 class="text-2xl md:text-3xl font-bold text-white">{@library.name}</h1>
        </div>

        <%!-- Stat / nav tiles --%>
        <div class="flex flex-wrap gap-2">
          <%= if @series_count > 0 do %>
            <a href={~p"/library/#{@library.id}/series"} class="group flex items-center gap-2.5 px-3 py-2 rounded-lg bg-gray-900 border border-gray-800 hover:border-violet-700/60 hover:bg-gray-800/60 transition-all">
              <.icon name="lucide-layers" class="w-4 h-4 text-violet-400 flex-shrink-0" />
              <span class="text-sm font-semibold text-white">{@series_count}</span>
              <span class="text-sm text-gray-400 group-hover:text-gray-300 transition-colors">Series</span>
              <.icon name="lucide-chevron-right" class="w-3.5 h-3.5 text-gray-600 group-hover:text-violet-400 transition-colors" />
            </a>
          <% end %>
          <%= if @books_count > 0 do %>
            <a href={~p"/library/#{@library.id}/books"} class="group flex items-center gap-2.5 px-3 py-2 rounded-lg bg-gray-900 border border-gray-800 hover:border-violet-700/60 hover:bg-gray-800/60 transition-all">
              <.icon name="lucide-book" class="w-4 h-4 text-violet-400 flex-shrink-0" />
              <span class="text-sm font-semibold text-white">{@books_count}</span>
              <span class="text-sm text-gray-400 group-hover:text-gray-300 transition-colors">Books</span>
              <.icon name="lucide-chevron-right" class="w-3.5 h-3.5 text-gray-600 group-hover:text-violet-400 transition-colors" />
            </a>
          <% end %>
          <%= if @issues_count > 0 do %>
            <a href={~p"/library/#{@library.id}/issues"} class="group flex items-center gap-2.5 px-3 py-2 rounded-lg bg-gray-900 border border-gray-800 hover:border-violet-700/60 hover:bg-gray-800/60 transition-all">
              <.icon name="lucide-newspaper" class="w-4 h-4 text-violet-400 flex-shrink-0" />
              <span class="text-sm font-semibold text-white">{@issues_count}</span>
              <span class="text-sm text-gray-400 group-hover:text-gray-300 transition-colors">Issues</span>
              <.icon name="lucide-chevron-right" class="w-3.5 h-3.5 text-gray-600 group-hover:text-violet-400 transition-colors" />
            </a>
          <% end %>
        </div>

        <%!-- Recent Series --%>
        <%= if @recent_series != [] do %>
          <section>
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-lg font-semibold text-gray-300 flex items-center gap-2">
                <span class="w-1 h-5 bg-violet-500 rounded-full inline-block"></span>
                Series
              </h2>
              <%= if @series_count > 20 do %>
                <a href={~p"/library/#{@library.id}/series"} class="text-sm text-violet-400 hover:text-violet-300">View all →</a>
              <% end %>
            </div>
            <div class="flex gap-4 overflow-x-auto pb-2 scrollbar-hide">
              <%= for s <- @recent_series do %>
                <.media_card
                  href={~p"/series/#{s.id}"}
                  title={s.name}
                  cover_url={~p"/api/series/#{s.id}/cover"}
                  width={288}
                  subtitle={series_date_range(s)}
                  badge={"#{s.issue_count} issues"}
                  type={:series}
                  class="flex-shrink-0 w-36"
                />
              <% end %>
            </div>
          </section>
        <% end %>

        <%!-- Recent Books --%>
        <%= if @recent_books != [] do %>
          <section>
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-lg font-semibold text-gray-300 flex items-center gap-2">
                <span class="w-1 h-5 bg-violet-500 rounded-full inline-block"></span>
                Books
              </h2>
              <%= if @books_count > 20 do %>
                <a href={~p"/library/#{@library.id}/books"} class="text-sm text-violet-400 hover:text-violet-300">View all →</a>
              <% end %>
            </div>
            <div class="flex gap-4 overflow-x-auto pb-2 scrollbar-hide">
              <%= for book <- @recent_books do %>
                <.media_card
                  href={~p"/book/#{book.id}"}
                  title={book.title}
                  cover_url={~p"/api/books/#{book.id}/cover"}
                  width={288}
                  subtitle={book.year && to_string(book.year)}
                  page_count={book.page_count}
                  type={:book}
                  class="flex-shrink-0 w-36"
                />
              <% end %>
            </div>
          </section>
        <% end %>

        <%!-- Recent Issues --%>
        <%= if @recent_issues != [] do %>
          <section>
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-lg font-semibold text-gray-300 flex items-center gap-2">
                <span class="w-1 h-5 bg-violet-500 rounded-full inline-block"></span>
                Issues
              </h2>
              <%= if @issues_count > 20 do %>
                <a href={~p"/library/#{@library.id}/issues"} class="text-sm text-violet-400 hover:text-violet-300">View all →</a>
              <% end %>
            </div>
            <div class="flex gap-4 overflow-x-auto pb-2 scrollbar-hide">
              <%= for book <- @recent_issues do %>
                <.media_card
                  href={~p"/book/#{book.id}"}
                  title={if book.issue_number, do: "##{book.issue_number} – #{book.title}", else: book.title}
                  cover_url={~p"/api/books/#{book.id}/cover"}
                  width={288}
                  subtitle={if book.series, do: book.series.name}
                  badge={
                    cond do
                      book.volume && book.issue_number -> "Vol #{book.volume}  ##{book.issue_number}"
                      book.issue_number -> "##{book.issue_number}"
                      true -> nil
                    end
                  }
                  type={:book}
                  class="flex-shrink-0 w-36"
                />
              <% end %>
            </div>
          </section>
        <% end %>

        <%= if @series_count == 0 && @books_count == 0 && @issues_count == 0 do %>
          <.browse_empty icon="lucide-library" label="No content in this library. Try scanning." />
        <% end %>

      <% else %>
        <%!-- Sub-page: Series / Books / Issues --%>
        <.browse_header
          title={@library.name}
          subtitle={"#{@total} #{section_label(@live_action) |> String.downcase()}"}
        >
          <:controls>
            <.sort_select options={@sort_options} selected={@sort} />
          </:controls>
        </.browse_header>

        <%= if @items != [] do %>
          <.pagination id="page-top" page={@page} total_pages={@total_pages} />

          <%= if @live_action == :series do %>
            <.media_grid>
              <%= for s <- @items do %>
                <.media_card
                  href={~p"/series/#{s.id}"}
                  title={s.name}
                  cover_url={~p"/api/series/#{s.id}/cover"}
                  width={300}
                  subtitle={series_date_range(s)}
                  badge={"#{s.issue_count} issues"}
                  type={:series}
                />
              <% end %>
            </.media_grid>
          <% end %>

          <%= if @live_action == :books do %>
            <.media_grid>
              <%= for book <- @items do %>
                <% prog = @progress_map[book.id] %>
                <% progress = if prog && book.page_count && book.page_count > 1, do: prog / (book.page_count - 1), else: nil %>
                <.media_card
                  href={~p"/book/#{book.id}"}
                  title={book.title}
                  cover_url={~p"/api/books/#{book.id}/cover"}
                  width={300}
                  subtitle={book.year && to_string(book.year)}
                  progress={progress}
                  page_count={book.page_count}
                  type={:book}
                />
              <% end %>
            </.media_grid>
          <% end %>

          <%= if @live_action == :issues do %>
            <.media_grid>
              <%= for book <- @items do %>
                <% prog = @progress_map[book.id] %>
                <% progress = if prog && book.page_count && book.page_count > 1, do: prog / (book.page_count - 1), else: nil %>
                <.media_card
                  href={~p"/book/#{book.id}"}
                  title={if book.issue_number, do: "##{book.issue_number} – #{book.title}", else: book.title}
                  cover_url={~p"/api/books/#{book.id}/cover"}
                  width={300}
                  subtitle={if book.series, do: book.series.name, else: book.year && to_string(book.year)}
                  progress={progress}
                  type={:book}
                />
              <% end %>
            </.media_grid>
          <% end %>

          <.pagination page={@page} total_pages={@total_pages} scroll_to="page-top" />
        <% end %>

        <%= if !@loading && @items == [] do %>
          <.browse_empty
            icon={if @live_action == :series, do: "lucide-layers", else: "lucide-book"}
            label={"No #{section_label(@live_action) |> String.downcase()} found."}
          />
        <% end %>
      <% end %>
    </div>
    """
  end
end
