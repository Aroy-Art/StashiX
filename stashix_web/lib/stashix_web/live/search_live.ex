defmodule StashixWeb.SearchLive do
  use StashixWeb, :live_view

  alias Stashix.Library

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @debounce_ms 300

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Search",
       query: "",
       results: [],
       search_timer: nil,
       searching: false
     )}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    if socket.assigns.search_timer do
      Process.cancel_timer(socket.assigns.search_timer)
    end

    timer = Process.send_after(self(), {:do_search, query}, @debounce_ms)
    {:noreply, assign(socket, query: query, search_timer: timer, searching: true)}
  end

  @impl true
  def handle_info({:do_search, query}, socket) do
    results =
      if String.length(query) >= 2 do
        Library.search_books(query, limit: 50)
      else
        []
      end

    {:noreply, assign(socket, results: results, searching: false, search_timer: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto space-y-6">
      <h1 class="text-2xl font-bold text-white">Search</h1>

      <div class="relative">
        <input
          type="text"
          value={@query}
          phx-keyup="search"
          name="q"
          placeholder="Search books, series, publishers..."
          class="w-full bg-gray-900 border border-gray-700 rounded-xl px-4 py-3 text-white placeholder-gray-500 focus:outline-none focus:border-indigo-500 text-lg"
          autofocus
        />
        <%= if @searching do %>
          <div class="absolute right-4 top-1/2 -translate-y-1/2 text-gray-500 text-sm">
            Searching...
          </div>
        <% end %>
      </div>

      <%= if @results != [] do %>
        <div>
          <p class="text-gray-500 text-sm mb-3">{length(@results)} results for "{@query}"</p>

          <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 gap-4">
            <%= for book <- @results do %>
              <.media_card
                href={~p"/book/#{book.id}"}
                title={book.title}
                cover_url={book.cover && ~p"/api/books/#{book.id}/cover"}
                subtitle={book.year && to_string(book.year)}
                badge={book.issue_number && "##{book.issue_number}"}
                type={:book}
              />
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if @query != "" && !@searching && @results == [] do %>
        <div class="text-center py-12 text-gray-500">
          No results found for "{@query}"
        </div>
      <% end %>
    </div>
    """
  end
end
