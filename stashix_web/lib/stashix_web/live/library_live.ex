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
       page: 0,
       books: [],
       series: [],
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

  def handle_event("load_more", _params, socket) do
    next_page = socket.assigns.page + 1
    library_id = socket.assigns.library.id
    filter = socket.assigns.filter
    opts = filter_opts(filter, next_page)
    new_books = Library.list_books(library_id, opts)
    {:noreply, update(socket, :books, &(&1 ++ new_books)) |> assign(:page, next_page)}
  end

  @impl true
  def handle_info({:scan_progress, _progress}, socket), do: {:noreply, socket}

  def handle_info({:book_added, _book}, socket) do
    {:noreply, load_content(socket, socket.assigns.filter, 0)}
  end

  defp load_content(socket, filter, page) do
    library_id = socket.assigns.library.id
    opts = filter_opts(filter, page)

    books =
      if filter in ["all", "issues", "standalone"] do
        Library.list_books(library_id, opts)
      else
        []
      end

    series =
      if filter in ["all", "series"] do
        Library.list_series(library_id)
      else
        []
      end

    assign(socket, books: books, series: series, loading: false)
  end

  defp filter_opts("issues", page),
    do: [type: "issue", limit: @page_size, offset: page * @page_size]

  defp filter_opts("standalone", page),
    do: [type: "standalone", limit: @page_size, offset: page * @page_size]

  defp filter_opts(_, page), do: [limit: @page_size, offset: page * @page_size]

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <a href="/" class="text-gray-500 hover:text-gray-300 text-sm">← Libraries</a>
          <h1 class="text-2xl font-bold text-white mt-1">{@library.name}</h1>
        </div>

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
      </div>

      <%= if @series != [] && @filter in ["all", "series"] do %>
        <section>
          <h2 class="text-lg font-semibold text-gray-300 mb-3">Series</h2>
          <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-8 gap-4">
            <%= for s <- @series do %>
              <a href={~p"/series/#{s.id}"} class="group">
                <div class="aspect-[2/3] bg-gray-800 rounded-lg overflow-hidden mb-1">
                  <div class="w-full h-full flex items-center justify-center text-gray-600">
                    <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
                    </svg>
                  </div>
                </div>
                <p class="text-xs text-gray-400 truncate group-hover:text-white">{s.name}</p>
                <p class="text-xs text-gray-600">{s.issue_count} issues</p>
              </a>
            <% end %>
          </div>
        </section>
      <% end %>

      <%= if @books != [] && @filter in ["all", "issues", "standalone"] do %>
        <section>
          <h2 class="text-lg font-semibold text-gray-300 mb-3">Books</h2>
          <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-8 gap-4">
            <%= for book <- @books do %>
              <a href={~p"/book/#{book.id}"} class="group">
                <div class="aspect-[2/3] bg-gray-800 rounded-lg overflow-hidden mb-1">
                  <%= if book.cover do %>
                    <img
                      src={~p"/api/books/#{book.id}/cover"}
                      alt={book.title}
                      class="w-full h-full object-cover group-hover:opacity-80 transition-opacity"
                    />
                  <% else %>
                    <div class="w-full h-full flex items-center justify-center text-gray-600">
                      <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
                      </svg>
                    </div>
                  <% end %>
                </div>
                <p class="text-xs text-gray-400 truncate group-hover:text-white">{book.title}</p>
                <%= if book.issue_number do %>
                  <p class="text-xs text-gray-600">#{book.issue_number}</p>
                <% end %>
              </a>
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
