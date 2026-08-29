defmodule StashixWeb.LibrariesLive do
  use StashixWeb, :live_view

  alias Stashix.Library

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    libraries = Library.list_libraries(user)

    libraries_data = Enum.map(libraries, &load_library_data/1)
    continue_reading = Library.in_progress_books(user.id, 20)
    next_issue = Library.next_issue_books(user.id, 20)

    {:ok,
     assign(socket,
       page_title: "Home",
       libraries_data: libraries_data,
       continue_reading: continue_reading,
       next_issue: next_issue,
       scan_progress: %{}
     )}
  end

  defp series_date_range(%{start_year: nil}), do: nil
  defp series_date_range(%{start_year: y, end_year: nil, ongoing: true}), do: "#{y}–"
  defp series_date_range(%{start_year: y, end_year: nil}), do: to_string(y)
  defp series_date_range(%{start_year: y, end_year: y}), do: to_string(y)
  defp series_date_range(%{start_year: s, end_year: e}), do: "#{s}–#{e}"

  defp load_library_data(lib) do
    recent_standalone = Library.recent_books(lib.id, 20, "standalone")
    recent_issues = Library.recent_issues(lib.id, 20)
    cover_books = Enum.take(recent_standalone ++ recent_issues, 5)

    %{
      library: lib,
      book_count: Library.count_books(lib.id),
      series_count: Library.count_series(lib.id),
      issue_count: Library.count_issues(lib.id),
      total_size: Library.total_size(lib.id),
      cover_books: cover_books,
      recent_books: recent_standalone,
      recent_series: Library.recent_series(lib.id, 20),
      recent_issues: recent_issues
    }
  end

  @impl true
  def handle_info({:scan_progress, %{library_id: lib_id, scanned: scanned, total: total, done: done}}, socket) do
    socket = update(socket, :scan_progress, &Map.put(&1, lib_id, %{scanned: scanned, total: total, done: done}))

    if done do
      Process.send_after(self(), {:clear_scan_progress, lib_id}, 3_000)
    end

    {:noreply, socket}
  end

  def handle_info({:scan_progress, %{library_id: lib_id, scanned: scanned, total: total}}, socket) do
    {:noreply,
     update(socket, :scan_progress, &Map.put(&1, lib_id, %{scanned: scanned, total: total, done: false}))}
  end

  def handle_info({:clear_scan_progress, lib_id}, socket) do
    {:noreply, update(socket, :scan_progress, &Map.delete(&1, lib_id))}
  end

  def handle_info({:book_added, _book}, socket) do
    user = socket.assigns.current_user
    libraries = Library.list_libraries(user)

    {:noreply,
     assign(socket,
       libraries_data: Enum.map(libraries, &load_library_data/1),
       continue_reading: Library.in_progress_books(user.id, 20),
       next_issue: Library.next_issue_books(user.id, 20)
     )}
  end

  @impl true
  def handle_event("scan", %{"id" => library_id}, socket) do
    Stashix.Scanner.scan_library(library_id)
    {:noreply, put_flash(socket, :info, "Scan started")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-10">

      <%!-- Libraries overview --%>
      <section>
        <h2 class="text-lg font-semibold text-white mb-4 flex items-center gap-2">
          <span class="w-1 h-5 bg-violet-500 rounded-full inline-block"></span>
          Libraries
        </h2>
        <div class="flex flex-wrap gap-4">
          <%= for %{library: lib, book_count: books, series_count: series, issue_count: issues, total_size: total_size, cover_books: covers} <- @libraries_data do %>
            <div class="w-72 bg-gray-900 rounded-xl border border-gray-800 overflow-hidden">
              <%!-- Cover mosaic --%>
              <div class="h-28 flex overflow-hidden relative bg-gray-800">
                <%= for book <- Enum.take(covers, 5) do %>
                  <div class="flex-1 min-w-0">
                    <img
                      src={~p"/api/books/#{book.id}/cover?w=200"}
                      class="w-full h-full object-cover"
                      onerror="this.style.display='none'"
                    />
                  </div>
                <% end %>
                <div class="absolute inset-0 bg-gradient-to-t from-gray-900/80 to-transparent"></div>
              </div>

              <div class="p-4">
                <div class="flex items-start justify-between mb-1">
                  <h3 class="font-semibold text-white truncate">{lib.name}</h3>
                  <%= if @current_user.role == :admin do %>
                    <button
                      phx-click="scan"
                      phx-value-id={lib.id}
                      class="text-xs text-gray-500 hover:text-white ml-2 flex-shrink-0"
                    >
                      Scan
                    </button>
                  <% end %>
                </div>

                <p class="text-xs text-gray-500 truncate mb-3">{lib.root_path}</p>

                <div class="flex flex-wrap gap-2 mb-3">
                  <span class="text-xs bg-violet-900/50 text-violet-300 border border-violet-800 px-2 py-0.5 rounded-full">{books} books</span>
                  <span class="text-xs bg-violet-900/50 text-violet-300 border border-violet-800 px-2 py-0.5 rounded-full">{issues} issues</span>
                  <span class="text-xs bg-violet-900/50 text-violet-300 border border-violet-800 px-2 py-0.5 rounded-full">{series} series</span>
                  <%= if total_size > 0 do %>
                    <span class="text-xs bg-gray-800 text-gray-400 border border-gray-700 px-2 py-0.5 rounded-full">{Stashix.Formatters.format_bytes(total_size)}</span>
                  <% end %>
                </div>

                <%= if progress = @scan_progress[lib.id] do %>
                  <%
                    collecting = progress.total == 0 and not progress.done
                    label = cond do
                      progress.done -> "Complete"
                      collecting -> "Collecting files..."
                      true -> "Scanning..."
                    end
                    pct = if progress.total > 0, do: round(progress.scanned / progress.total * 100), else: 0
                  %>
                  <div class={"mb-3 transition-opacity duration-1000 #{if progress.done, do: "opacity-0", else: "opacity-100"}"}>
                    <div class="flex justify-between text-xs text-gray-500 mb-1">
                      <span>{label}</span>
                      <%= if not collecting do %>
                        <span>{progress.scanned}/{progress.total}</span>
                      <% end %>
                    </div>
                    <div class="h-1 bg-gray-800 rounded-full overflow-hidden">
                      <div
                        class={"h-full transition-all #{cond do progress.done -> "bg-green-500"; collecting -> "bg-violet-500 animate-pulse w-full"; true -> "bg-violet-500" end}"}
                        style={if collecting, do: "", else: "width: #{pct}%"}
                      ></div>
                    </div>
                  </div>
                <% end %>

                <a href={~p"/library/#{lib.id}"} class="text-sm text-violet-400 hover:text-violet-300">
                  Browse collection →
                </a>
              </div>
            </div>
          <% end %>
        </div>
      </section>

      <%!-- Continue Reading --%>
      <%= if @continue_reading != [] do %>
        <section>
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-lg font-semibold text-white flex items-center gap-2">
              <span class="w-1 h-5 bg-violet-500 rounded-full inline-block"></span>
              Continue Reading
            </h2>
            <div class="flex gap-1">
              <button onclick="document.getElementById('continue-reading').scrollBy({left:-600,behavior:'smooth'})" class="p-1 rounded text-gray-500 hover:text-white hover:bg-gray-800">
                <.icon name="lucide-chevron-left" class="w-5 h-5" />
              </button>
              <button onclick="document.getElementById('continue-reading').scrollBy({left:600,behavior:'smooth'})" class="p-1 rounded text-gray-500 hover:text-white hover:bg-gray-800">
                <.icon name="lucide-chevron-right" class="w-5 h-5" />
              </button>
            </div>
          </div>
          <div id="continue-reading" class="flex gap-4 overflow-x-auto pb-2 scrollbar-hide">
            <%= for %{book: book, current_page: current_page} <- @continue_reading do %>
              <% progress = if book.page_count && book.page_count > 1, do: current_page / (book.page_count - 1), else: nil %>
              <.media_card
                href={~p"/book/#{book.id}"}
                title={if book.issue_number, do: "##{book.issue_number} – #{book.title}", else: book.title}
                cover_url={~p"/api/books/#{book.id}/cover"}
                width={288}
                subtitle={
                  cond do
                    book.type == "issue" && book.issue_number && book.series && book.series.issue_count > 0 ->
                      "Issue ##{book.issue_number} of #{book.series.issue_count}"
                    book.type == "issue" && book.issue_number ->
                      "Issue ##{book.issue_number}"
                    book.type == "issue" ->
                      "Issue"
                    true ->
                      "Standalone"
                  end
                }
                progress={progress}
                type={:book}
                class="flex-shrink-0 w-36"
              />
            <% end %>
          </div>
        </section>
      <% end %>

      <%!-- Next Issue --%>
      <%= if @next_issue != [] do %>
        <section>
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-lg font-semibold text-white flex items-center gap-2">
              <span class="w-1 h-5 bg-violet-500 rounded-full inline-block"></span>
              Next Issue
            </h2>
            <div class="flex gap-1">
              <button onclick="document.getElementById('next-issue').scrollBy({left:-600,behavior:'smooth'})" class="p-1 rounded text-gray-500 hover:text-white hover:bg-gray-800">
                <.icon name="lucide-chevron-left" class="w-5 h-5" />
              </button>
              <button onclick="document.getElementById('next-issue').scrollBy({left:600,behavior:'smooth'})" class="p-1 rounded text-gray-500 hover:text-white hover:bg-gray-800">
                <.icon name="lucide-chevron-right" class="w-5 h-5" />
              </button>
            </div>
          </div>
          <div id="next-issue" class="flex gap-4 overflow-x-auto pb-2 scrollbar-hide">
            <%= for book <- @next_issue do %>
              <.media_card
                href={~p"/book/#{book.id}"}
                title={if book.issue_number, do: "##{book.issue_number} – #{book.title}", else: book.title}
                cover_url={~p"/api/books/#{book.id}/cover"}
                width={288}
                subtitle={if book.series, do: book.series.name, else: nil}
                type={:book}
                class="flex-shrink-0 w-36"
              />
            <% end %>
          </div>
        </section>
      <% end %>

      <%!-- Per-library sections --%>
      <%= for %{library: lib, recent_books: books, recent_series: series, recent_issues: issues} <- @libraries_data do %>

        <%!-- Recent Books --%>
        <%= if books != [] do %>
          <section>
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-lg font-semibold text-white flex items-center gap-2">
                <span class="w-1 h-5 bg-violet-500 rounded-full inline-block"></span>
                {lib.name} — Recent Books
              </h2>
              <div class="flex gap-1">
                <button onclick={"document.getElementById('books-#{lib.id}').scrollBy({left:-600,behavior:'smooth'})"} class="p-1 rounded text-gray-500 hover:text-white hover:bg-gray-800">
                  <.icon name="lucide-chevron-left" class="w-5 h-5" />
                </button>
                <button onclick={"document.getElementById('books-#{lib.id}').scrollBy({left:600,behavior:'smooth'})"} class="p-1 rounded text-gray-500 hover:text-white hover:bg-gray-800">
                  <.icon name="lucide-chevron-right" class="w-5 h-5" />
                </button>
              </div>
            </div>
            <div id={"books-#{lib.id}"} class="flex gap-4 overflow-x-auto pb-2 scrollbar-hide">
              <%= for book <- books do %>
                <.media_card
                  href={~p"/book/#{book.id}"}
                  title={if book.issue_number, do: "##{book.issue_number} – #{book.title}", else: book.title}
                  cover_url={~p"/api/books/#{book.id}/cover"}
                  width={288}
                  subtitle={book.year && to_string(book.year)}
                  type={:book}
                  class="flex-shrink-0 w-36"
                />
              <% end %>
            </div>
          </section>
        <% end %>

        <%!-- Recent Series --%>
        <%= if series != [] do %>
          <section>
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-lg font-semibold text-white flex items-center gap-2">
                <span class="w-1 h-5 bg-violet-500 rounded-full inline-block"></span>
                {lib.name} — Recent Series
              </h2>
              <div class="flex gap-1">
                <button onclick={"document.getElementById('series-#{lib.id}').scrollBy({left:-600,behavior:'smooth'})"} class="p-1 rounded text-gray-500 hover:text-white hover:bg-gray-800">
                  <.icon name="lucide-chevron-left" class="w-5 h-5" />
                </button>
                <button onclick={"document.getElementById('series-#{lib.id}').scrollBy({left:600,behavior:'smooth'})"} class="p-1 rounded text-gray-500 hover:text-white hover:bg-gray-800">
                  <.icon name="lucide-chevron-right" class="w-5 h-5" />
                </button>
              </div>
            </div>
            <div id={"series-#{lib.id}"} class="flex gap-4 overflow-x-auto pb-2 scrollbar-hide">
              <%= for s <- series do %>
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

        <%!-- Recent Issues --%>
        <%= if issues != [] do %>
          <section>
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-lg font-semibold text-white flex items-center gap-2">
                <span class="w-1 h-5 bg-violet-500 rounded-full inline-block"></span>
                {lib.name} — Recent Issues
              </h2>
              <div class="flex gap-1">
                <button onclick={"document.getElementById('issues-#{lib.id}').scrollBy({left:-600,behavior:'smooth'})"} class="p-1 rounded text-gray-500 hover:text-white hover:bg-gray-800">
                  <.icon name="lucide-chevron-left" class="w-5 h-5" />
                </button>
                <button onclick={"document.getElementById('issues-#{lib.id}').scrollBy({left:600,behavior:'smooth'})"} class="p-1 rounded text-gray-500 hover:text-white hover:bg-gray-800">
                  <.icon name="lucide-chevron-right" class="w-5 h-5" />
                </button>
              </div>
            </div>
            <div id={"issues-#{lib.id}"} class="flex gap-4 overflow-x-auto pb-2 scrollbar-hide">
              <%= for book <- issues do %>
                <.media_card
                  href={~p"/book/#{book.id}"}
                  title={if book.issue_number, do: "##{book.issue_number} – #{book.title}", else: book.title}
                  cover_url={~p"/api/books/#{book.id}/cover"}
                  width={288}
                  subtitle={book.year && to_string(book.year)}
                  type={:book}
                  class="flex-shrink-0 w-36"
                />
              <% end %>
            </div>
          </section>
        <% end %>

      <% end %>
    </div>
    """
  end
end
