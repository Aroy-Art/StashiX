defmodule StashixWeb.BookLive do
  use StashixWeb, :live_view

  alias Stashix.Library

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    book = Library.get_book_with_series(id)
    library = Library.get_library!(book.library_id)

    progress = Library.get_progress(socket.assigns.current_user.id, id)
    current_page = (progress && progress.current_page) || 0

    {:ok,
     assign(socket,
       page_title: book.title,
       book: book,
       library: library,
       progress: current_page
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto space-y-6">
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
        <%= if @book.series do %>
          <span class="text-gray-700">/</span>
          <a href={~p"/series/#{@book.series.id}"} class="text-gray-500 hover:text-gray-300">{@book.series.name}</a>
        <% end %>
        <span class="text-gray-700">/</span>
        <span class="text-gray-300">{@book.title}</span>
      </div>

      <div class="flex gap-8">
        <div class="w-48 flex-shrink-0">
          <div class="aspect-[2/3] bg-gray-800 rounded-xl overflow-hidden">
            <%= if @book.cover do %>
              <img
                src={~p"/api/books/#{@book.id}/cover"}
                alt={@book.title}
                class="w-full h-full object-cover"
              />
            <% else %>
              <div class="w-full h-full flex items-center justify-center text-gray-600">
                <svg class="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
                </svg>
              </div>
            <% end %>
          </div>
        </div>

        <div class="flex-1">
          <h1 class="text-3xl font-bold text-white">{@book.title}</h1>

          <div class="mt-4 grid grid-cols-2 gap-3 text-sm">
            <%= if @book.issue_number do %>
              <div>
                <span class="text-gray-500">Issue</span>
                <span class="text-gray-200 ml-2">#{@book.issue_number}</span>
              </div>
            <% end %>
            <%= if @book.year do %>
              <div>
                <span class="text-gray-500">Year</span>
                <span class="text-gray-200 ml-2">{@book.year}</span>
              </div>
            <% end %>
            <div>
              <span class="text-gray-500">Pages</span>
              <span class="text-gray-200 ml-2">{@book.page_count}</span>
            </div>
            <div>
              <span class="text-gray-500">Format</span>
              <span class="text-gray-200 ml-2 uppercase">{@book.format}</span>
            </div>
            <%= if @book.language do %>
              <div>
                <span class="text-gray-500">Language</span>
                <span class="text-gray-200 ml-2">{@book.language}</span>
              </div>
            <% end %>
            <div class="col-span-2">
              <span class="text-gray-500">File</span>
              <span class="text-gray-400 ml-2 font-mono text-xs break-all">
                {@library.name <> "/" <> (String.replace_prefix(@book.path, @library.root_path, "") |> String.trim_leading("/"))}
              </span>
            </div>
          </div>

          <%= if @book.summary && @book.summary != "" do %>
            <p class="mt-4 text-gray-400 text-sm leading-relaxed">{@book.summary}</p>
          <% end %>

          <%= if @book.page_count > 0 do %>
            <div class="mt-6">
              <%= if @progress > 0 do %>
                <div class="mb-2">
                  <div class="flex justify-between text-xs text-gray-500 mb-1">
                    <span>Progress</span>
                    <span>{@progress}/{@book.page_count} pages</span>
                  </div>
                  <div class="h-1.5 bg-gray-800 rounded-full overflow-hidden">
                    <div
                      class="h-full bg-indigo-500"
                      style={"width: #{round(@progress / @book.page_count * 100)}%"}
                    >
                    </div>
                  </div>
                </div>
              <% end %>

              <a
                href={~p"/read/#{@book.id}"}
                class="inline-flex items-center gap-2 px-6 py-2.5 bg-indigo-600 hover:bg-indigo-500 text-white font-medium rounded-lg transition-colors"
              >
                <%= if @progress > 0 do %>
                  Continue Reading
                <% else %>
                  Read Now
                <% end %>
              </a>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
