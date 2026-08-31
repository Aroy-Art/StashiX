defmodule StashixWeb.LibraryLive do
  use StashixWeb, :live_view

  alias Stashix.Library

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @page_size 48

  @impl true
  def mount(%{"id" => library_id}, _session, socket) do
    library = Library.get_library!(library_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Stashix.PubSub, "scan:#{library_id}")
    end

    {:ok,
     assign(socket,
       page_title: library.name,
       library: library,
       filter: "all",
       sort: "title_asc",
       page: 0,
       books: [],
       series: [],
       progress_map: %{},
       loading: true
     )
     |> load_content("all", 0)}
  end

  @impl true
  def handle_params(%{"filter" => filter}, _uri, socket) do
    {:noreply, load_content(socket, filter, 0) |> assign(filter: filter, page: 0)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("filter", %{"value" => filter}, socket) do
    {:noreply, load_content(assign(socket, filter: filter, page: 0), filter, 0)}
  end

  def handle_event("sort", %{"value" => sort}, socket) do
    {:noreply, load_content(assign(socket, sort: sort, page: 0), socket.assigns.filter, 0)}
  end

  def handle_event("load_more", _params, socket) do
    next_page = socket.assigns.page + 1
    library_id = socket.assigns.library.id
    filter = socket.assigns.filter
    sort = socket.assigns.sort
    user_id = socket.assigns.current_user.id
    opts = filter_opts(filter, next_page, sort)
    new_books = Library.list_books(library_id, opts)
    new_progress = Library.progress_map(user_id, Enum.map(new_books, & &1.id))

    {:noreply,
     socket
     |> update(:books, &(&1 ++ new_books))
     |> update(:progress_map, &Map.merge(&1, new_progress))
     |> assign(:page, next_page)}
  end

  @impl true
  def handle_info({:scan_progress, _progress}, socket), do: {:noreply, socket}

  def handle_info({:book_added, _book}, socket) do
    {:noreply, load_content(socket, socket.assigns.filter, 0)}
  end

  defp series_date_range(%{start_year: nil}), do: nil
  defp series_date_range(%{start_year: y, end_year: nil, ongoing: true}), do: "#{y}–"
  defp series_date_range(%{start_year: y, end_year: nil}), do: to_string(y)
  defp series_date_range(%{start_year: y, end_year: y}), do: to_string(y)
  defp series_date_range(%{start_year: s, end_year: e}), do: "#{s}–#{e}"

  defp load_content(socket, filter, page) do
    library_id = socket.assigns.library.id
    user_id = socket.assigns.current_user.id
    sort = socket.assigns.sort
    opts = filter_opts(filter, page, sort)

    books =
      if filter in ["all", "issues", "standalone"] do
        Library.list_books(library_id, opts)
      else
        []
      end

    series =
      if filter in ["all", "series"] do
        Library.list_series(library_id, sort: sort)
      else
        []
      end

    progress_map = Library.progress_map(user_id, Enum.map(books, & &1.id))

    assign(socket, books: books, series: series, progress_map: progress_map, loading: false)
  end

  defp sort_options("issues") do
    [
      {"A → Z", "title_asc"},
      {"Z → A", "title_desc"},
      {"Issue # ↑", "issue_asc"},
      {"Issue # ↓", "issue_desc"},
      {"Year ↑", "year_asc"},
      {"Year ↓", "year_desc"},
      {"Date Added ↓", "added_desc"},
      {"Date Added ↑", "added_asc"}
    ]
  end

  defp sort_options(_filter) do
    [
      {"A → Z", "title_asc"},
      {"Z → A", "title_desc"},
      {"Year ↑", "year_asc"},
      {"Year ↓", "year_desc"},
      {"Date Added ↓", "added_desc"},
      {"Date Added ↑", "added_asc"}
    ]
  end

  defp filter_opts("issues", page, sort),
    do: [type: "issue", limit: @page_size, offset: page * @page_size, sort: sort]

  defp filter_opts("standalone", page, sort),
    do: [type: "standalone", limit: @page_size, offset: page * @page_size, sort: sort]

  defp filter_opts(_, page, sort), do: [limit: @page_size, offset: page * @page_size, sort: sort]

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <a href="/" class="text-gray-500 hover:text-gray-300 text-sm">← Libraries</a>
          <h1 class="text-2xl font-bold text-white mt-1">{@library.name}</h1>
        </div>

        <div class="flex items-center gap-3">
          <div class="flex gap-2">
            <%= for {label, value} <- [{"All", "all"}, {"Series", "series"}, {"Issues", "issues"}, {"Standalone", "standalone"}] do %>
              <button
                phx-click="filter"
                phx-value-value={value}
                class={[
                  "px-3 py-1 text-sm rounded-lg border transition-colors",
                  if(@filter == value,
                    do: "bg-indigo-600 border-indigo-500 text-white",
                    else: "bg-gray-800 border-gray-700 text-gray-400 hover:text-white"
                  )
                ]}
              >
                {label}
              </button>
            <% end %>
          </div>

          <.separator orientation="vertical" class="h-5 mx-1" />

          <form phx-change="sort">
            <select
              name="value"
              class="px-3 py-1 text-sm rounded-lg border bg-gray-800 border-gray-700 text-gray-400 hover:text-white focus:outline-none focus:border-indigo-500 cursor-pointer"
            >
              <%= for {label, value} <- sort_options(@filter) do %>
                <option value={value} selected={@sort == value}>{label}</option>
              <% end %>
            </select>
          </form>
        </div>
      </div>

      <%= if @series != [] && @filter in ["all", "series"] do %>
        <section>
          <h2 class="text-lg font-semibold text-gray-300 mb-3">Series</h2>
          <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-4 lg:grid-cols-6 xl:grid-cols-8 gap-4">
            <%= for s <- @series do %>
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
          </div>
        </section>
      <% end %>

      <%= if @books != [] && @filter in ["all", "issues", "standalone"] do %>
        <section>
          <h2 class="text-lg font-semibold text-gray-300 mb-3">Books</h2>
          <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-4 lg:grid-cols-6 xl:grid-cols-8 gap-4">
            <%= for book <- @books do %>
              <% prog = @progress_map[book.id] %>
              <% progress = if prog && book.page_count && book.page_count > 1, do: prog / (book.page_count - 1), else: nil %>
              <.media_card
                href={~p"/book/#{book.id}"}
                title={if book.issue_number, do: "##{book.issue_number} – #{book.title}", else: book.title}
                cover_url={~p"/api/books/#{book.id}/cover"}
                width={300}
                subtitle={book.year && to_string(book.year)}
                progress={progress}
                type={:book}
              />
            <% end %>
          </div>
          <div class="mt-6 text-center">
            <button
              phx-click="load_more"
              class="px-4 py-2 bg-gray-800 hover:bg-gray-700 text-gray-300 text-sm rounded-lg border border-gray-700"
            >
              Load More
            </button>
          </div>
        </section>
      <% end %>

      <%= if !@loading && @books == [] && @series == [] do %>
        <div class="text-center py-16 text-gray-500">
          <p>No items found. Try scanning the library.</p>
        </div>
      <% end %>
    </div>
    """
  end
end
