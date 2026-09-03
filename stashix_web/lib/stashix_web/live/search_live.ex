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
       results: %{series: [], issues: [], books: []},
       search_timer: nil,
       searching: false
     )}
  end

  @impl true
  def handle_params(%{"q" => query}, _uri, socket) when query != "" do
    send(self(), {:do_search, query})
    {:noreply, assign(socket, query: query, searching: true)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"value" => query}, socket) do
    if socket.assigns.search_timer do
      Process.cancel_timer(socket.assigns.search_timer)
    end

    timer = Process.send_after(self(), {:do_search, query}, @debounce_ms)

    {:noreply,
     socket
     |> assign(query: query, search_timer: timer, searching: true)
     |> push_patch(to: ~p"/search?#{if query != "", do: [q: query], else: []}", replace: true)}
  end

  @impl true
  def handle_info({:scan_progress, _}, socket), do: {:noreply, socket}
  def handle_info({:book_added, _}, socket), do: {:noreply, socket}

  def handle_info({:do_search, query}, socket) do
    results =
      if String.length(query) >= 2 do
        Library.search_all(query, limit: 20)
      else
        %{series: [], issues: [], books: []}
      end

    {:noreply, assign(socket, results: results, searching: false, search_timer: nil)}
  end

  defp total_results(%{series: s, issues: i, books: b}), do: length(s) + length(i) + length(b)

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

      <%= if total_results(@results) > 0 do %>
        <p class="text-gray-500 text-sm">{total_results(@results)} results for "{@query}"</p>

        <%= if @results.series != [] do %>
          <section class="space-y-3">
            <h2 class="text-sm font-semibold uppercase tracking-widest text-gray-400">Series</h2>
            <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 gap-4">
              <%= for s <- @results.series do %>
                <.media_card
                  href={~p"/series/#{s.id}"}
                  title={s.name}
                  cover_url={~p"/api/series/#{s.id}/cover"}
                  width={300}
                  subtitle={s.start_year && to_string(s.start_year)}
                  badge={"#{s.issue_count} issues"}
                  type={:series}
                />
              <% end %>
            </div>
          </section>
        <% end %>

        <%= if @results.issues != [] do %>
          <section class="space-y-3">
            <h2 class="text-sm font-semibold uppercase tracking-widest text-gray-400">Issues</h2>
            <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 gap-4">
              <%= for book <- @results.issues do %>
                <.media_card
                  href={~p"/book/#{book.id}"}
                  title={if book.issue_number, do: "##{book.issue_number} – #{book.title}", else: book.title}
                  cover_url={book.cover && ~p"/api/books/#{book.id}/cover"}
                  width={300}
                  subtitle={book.series && book.series.name}
                  badge={
                    cond do
                      book.volume && book.issue_number -> "Vol #{book.volume}  ##{book.issue_number}"
                      book.issue_number -> "##{book.issue_number}"
                      true -> nil
                    end
                  }
                  type={:book}
                />
              <% end %>
            </div>
          </section>
        <% end %>

        <%= if @results.books != [] do %>
          <section class="space-y-3">
            <h2 class="text-sm font-semibold uppercase tracking-widest text-gray-400">Books</h2>
            <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 gap-4">
              <%= for book <- @results.books do %>
                <.media_card
                  href={~p"/book/#{book.id}"}
                  title={book.title}
                  cover_url={book.cover && ~p"/api/books/#{book.id}/cover"}
                  width={300}
                  subtitle={book.year && to_string(book.year)}
                  type={:book}
                />
              <% end %>
            </div>
          </section>
        <% end %>
      <% end %>

      <%= if @query != "" && !@searching && total_results(@results) == 0 do %>
        <div class="text-center py-12 text-gray-500">
          No results found for "{@query}"
        </div>
      <% end %>
    </div>
    """
  end
end
