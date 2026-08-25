defmodule StashixWeb.LibrariesLive do
  use StashixWeb, :live_view

  alias Stashix.Library

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    libraries = Library.list_libraries(user)

    libraries_with_stats =
      Enum.map(libraries, fn lib ->
        %{
          library: lib,
          book_count: Library.count_books(lib.id),
          series_count: Library.count_series(lib.id),
          recent_books: Library.recent_books(lib.id, 6)
        }
      end)

    if connected?(socket) do
      Enum.each(libraries, fn lib ->
        Phoenix.PubSub.subscribe(Stashix.PubSub, "scan:#{lib.id}")
      end)
    end

    {:ok,
     assign(socket,
       page_title: "Libraries",
       libraries: libraries_with_stats,
       scan_progress: %{}
     )}
  end

  @impl true
  def handle_info({:scan_progress, %{library_id: lib_id, scanned: scanned, total: total}}, socket) do
    {:noreply,
     update(socket, :scan_progress, &Map.put(&1, lib_id, %{scanned: scanned, total: total}))}
  end

  def handle_info({:book_added, _book}, socket) do
    user = socket.assigns.current_user
    libraries = Library.list_libraries(user)

    libraries_with_stats =
      Enum.map(libraries, fn lib ->
        %{
          library: lib,
          book_count: Library.count_books(lib.id),
          series_count: Library.count_series(lib.id),
          recent_books: Library.recent_books(lib.id, 6)
        }
      end)

    {:noreply, assign(socket, :libraries, libraries_with_stats)}
  end

  @impl true
  def handle_event("scan", %{"id" => library_id}, socket) do
    Stashix.Scanner.scan_library(library_id)
    {:noreply, put_flash(socket, :info, "Scan started")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-white">Libraries</h1>
        <%= if @current_user.role == :admin do %>
          <a href="/admin" class="text-sm text-indigo-400 hover:text-indigo-300">
            Admin Panel
          </a>
        <% end %>
      </div>

      <%= if @libraries == [] do %>
        <div class="text-center py-16 text-gray-500">
          <p class="text-lg">No libraries yet.</p>
          <%= if @current_user.role == :admin do %>
            <p class="mt-2">Create a library from the Admin Panel.</p>
          <% end %>
        </div>
      <% end %>

      <%= for %{library: lib, book_count: books, series_count: series, recent_books: recents} <- @libraries do %>
        <div class="bg-gray-900 rounded-xl border border-gray-800 p-6">
          <div class="flex items-start justify-between mb-4">
            <div>
              <a href={~p"/library/#{lib.id}"} class="text-xl font-semibold text-white hover:text-indigo-300">
                {lib.name}
              </a>
              <p class="text-gray-500 text-sm mt-1">{lib.root_path}</p>
            </div>

            <div class="flex items-center gap-4">
              <div class="text-right text-sm text-gray-400">
                <span>{books} books</span>
                <span class="mx-2">·</span>
                <span>{series} series</span>
              </div>

              <%= if @current_user.role == :admin do %>
                <button
                  phx-click="scan"
                  phx-value-id={lib.id}
                  class="px-3 py-1 text-sm bg-gray-800 hover:bg-gray-700 text-gray-300 rounded-lg border border-gray-700"
                >
                  Scan
                </button>
              <% end %>
            </div>
          </div>

          <%= if progress = @scan_progress[lib.id] do %>
            <div class="mb-4">
              <div class="flex justify-between text-xs text-gray-500 mb-1">
                <span>Scanning...</span>
                <span>{progress.scanned}/{progress.total}</span>
              </div>
              <div class="h-1 bg-gray-800 rounded-full overflow-hidden">
                <div
                  class="h-full bg-indigo-500 transition-all"
                  style={"width: #{if progress.total > 0, do: round(progress.scanned / progress.total * 100), else: 0}%"}
                >
                </div>
              </div>
            </div>
          <% end %>

          <%= if recents != [] do %>
            <div class="grid grid-cols-3 sm:grid-cols-6 gap-3 mt-4">
              <%= for book <- recents do %>
                <a href={~p"/book/#{book.id}"} class="group">
                  <div class="aspect-[2/3] bg-gray-800 rounded-lg overflow-hidden">
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
                  <p class="text-xs text-gray-400 mt-1 truncate">{book.title}</p>
                </a>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
