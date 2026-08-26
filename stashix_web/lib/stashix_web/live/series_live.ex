defmodule StashixWeb.SeriesLive do
  use StashixWeb, :live_view

  alias Stashix.Library

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    series = Library.get_series_with_books(id)
    library = Library.get_library!(series.library_id)

    {:ok,
     assign(socket,
       page_title: series.name,
       series: series,
       library: library,
       books: series.books
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center gap-2 text-sm">
        <button onclick="history.back()" class="text-gray-500 hover:text-gray-300 flex items-center gap-1">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
          </svg>
          Back
        </button>
        <span class="text-gray-700">/</span>
        <a href="/" class="text-gray-500 hover:text-gray-300">Home</a>
        <span class="text-gray-700">/</span>
        <a href={~p"/library/#{@library.id}"} class="text-gray-500 hover:text-gray-300">{@library.name}</a>
        <span class="text-gray-700">/</span>
        <span class="text-gray-300">{@series.name}</span>
      </div>

      <div class="flex gap-6">
        <div class="w-32 flex-shrink-0">
          <div class="aspect-[2/3] bg-gray-800 rounded-lg overflow-hidden">
            <div class="w-full h-full flex items-center justify-center text-gray-600">
              <svg class="w-10 h-10" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
              </svg>
            </div>
          </div>
        </div>

        <div class="flex-1">
          <h1 class="text-3xl font-bold text-white">{@series.name}</h1>
          <%= if @series.volume do %>
            <p class="text-gray-400 mt-1">Volume {@series.volume}</p>
          <% end %>
          <div class="flex gap-4 mt-3 text-sm text-gray-500">
            <span>{length(@books)} issues</span>
            <%= if @series.language do %>
              <span>Language: {@series.language}</span>
            <% end %>
            <span class={if @series.ongoing, do: "text-green-500", else: "text-gray-500"}>
              {if @series.ongoing, do: "Ongoing", else: "Completed"}
            </span>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-8 gap-4">
        <%= for book <- @books do %>
          <.media_card
            href={~p"/book/#{book.id}"}
            title={if book.issue_number, do: "##{book.issue_number} – #{book.title}", else: book.title}
            cover_url={~p"/api/books/#{book.id}/cover"}
            width={300}
            subtitle={book.year && to_string(book.year)}
            type={:book}
          />
        <% end %>
      </div>
    </div>
    """
  end
end
