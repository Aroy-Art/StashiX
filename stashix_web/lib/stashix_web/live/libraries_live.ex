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

    total_books = Library.count_all_books(type: "standalone")
    total_issues = Library.count_all_books(type: "issue")
    total_series = Library.count_all_series([])

    {:ok,
     assign(socket,
       page_title: "Home",
       libraries_data: libraries_data,
       continue_reading: continue_reading,
       next_issue: next_issue,
       scan_progress: %{},
       total_books: total_books,
       total_issues: total_issues,
       total_series: total_series
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
       next_issue: Library.next_issue_books(user.id, 20),
       total_books: Library.count_all_books(type: "standalone"),
       total_issues: Library.count_all_books(type: "issue"),
       total_series: Library.count_all_series([])
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-10">

      <%!-- Stats + section navigation --%>
      <%!-- <section>
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <a href={~p"/books"} class="group flex items-center gap-4 p-5 rounded-xl bg-gray-900 border border-gray-800 hover:border-violet-700/60 hover:bg-gray-800/60 transition-all">
            <div class="w-10 h-10 flex items-center justify-center rounded-lg bg-violet-900/40 text-violet-400 group-hover:bg-violet-800/60 transition-colors flex-shrink-0">
              <.icon name="lucide-book" class="w-5 h-5" />
            </div>
            <div class="min-w-0">
              <p class="text-2xl font-bold text-white">{@total_books}</p>
              <p class="text-sm text-gray-400 group-hover:text-gray-300 transition-colors">Books</p>
            </div>
            <.icon name="lucide-chevron-right" class="w-4 h-4 text-gray-600 group-hover:text-violet-400 ml-auto transition-colors" />
          </a>

          <a href={~p"/series"} class="group flex items-center gap-4 p-5 rounded-xl bg-gray-900 border border-gray-800 hover:border-violet-700/60 hover:bg-gray-800/60 transition-all">
            <div class="w-10 h-10 flex items-center justify-center rounded-lg bg-violet-900/40 text-violet-400 group-hover:bg-violet-800/60 transition-colors flex-shrink-0">
              <.icon name="lucide-layers" class="w-5 h-5" />
            </div>
            <div class="min-w-0">
              <p class="text-2xl font-bold text-white">{@total_series}</p>
              <p class="text-sm text-gray-400 group-hover:text-gray-300 transition-colors">Series</p>
            </div>
            <.icon name="lucide-chevron-right" class="w-4 h-4 text-gray-600 group-hover:text-violet-400 ml-auto transition-colors" />
          </a>

          <a href={~p"/issues"} class="group flex items-center gap-4 p-5 rounded-xl bg-gray-900 border border-gray-800 hover:border-violet-700/60 hover:bg-gray-800/60 transition-all">
            <div class="w-10 h-10 flex items-center justify-center rounded-lg bg-violet-900/40 text-violet-400 group-hover:bg-violet-800/60 transition-colors flex-shrink-0">
              <.icon name="lucide-newspaper" class="w-5 h-5" />
            </div>
            <div class="min-w-0">
              <p class="text-2xl font-bold text-white">{@total_issues}</p>
              <p class="text-sm text-gray-400 group-hover:text-gray-300 transition-colors">Issues</p>
            </div>
            <.icon name="lucide-chevron-right" class="w-4 h-4 text-gray-600 group-hover:text-violet-400 ml-auto transition-colors" />
          </a>
        </div>
      </section> --%>

      <%!-- Libraries --%>
      <section>
        <h2 class="text-lg font-semibold text-white mb-4 flex items-center gap-2">
          <span class="w-1 h-5 bg-violet-500 rounded-full inline-block"></span>
          Libraries
        </h2>
        <div class="flex flex-wrap gap-4">
          <%= for %{library: lib, book_count: books, series_count: series, issue_count: issues, total_size: total_size, cover_books: covers} <- @libraries_data do %>
            <.card class="w-72 bg-gray-900 border-gray-800 overflow-hidden">
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

              <.card_content class="p-4">
                <div class="flex items-start justify-between mb-1">
                  <h3 class="font-semibold text-white truncate">{lib.name}</h3>
                  <%= if @current_user.role == :admin do %>
                    <.dropdown_menu id={"card-menu-#{lib.id}"}>
                      <.dropdown_menu_trigger class="p-1 rounded text-gray-500 hover:text-white hover:bg-gray-700 transition-all ml-1 flex-shrink-0">
                        <.icon name="lucide-ellipsis-vertical" class="w-3.5 h-3.5" />
                      </.dropdown_menu_trigger>
                      <.dropdown_menu_content align="end" class="bg-gray-800 border-gray-700 text-gray-300 whitespace-nowrap">
                        <.dropdown_menu_item
                          class="hover:bg-gray-700 focus:bg-gray-700 cursor-pointer"
                          on-select={JS.push("sidebar_scan", value: %{id: lib.id})}
                        >
                          <.icon name="lucide-refresh-cw" class="w-3.5 h-3.5 mr-2 shrink-0" />
                          Scan for new files
                        </.dropdown_menu_item>
                        <.dropdown_menu_item
                          class="hover:bg-gray-700 focus:bg-gray-700 cursor-pointer"
                          on-select={JS.push("sidebar_force_scan", value: %{id: lib.id})}
                        >
                          <.icon name="lucide-rotate-ccw" class="w-3.5 h-3.5 mr-2 shrink-0" />
                          Force rescan
                        </.dropdown_menu_item>
                        <.dropdown_menu_separator class="bg-gray-700" />
                        <.dropdown_menu_link_item href="/admin" class="hover:bg-gray-700 focus:bg-gray-700">
                          <.icon name="lucide-settings" class="w-3.5 h-3.5 mr-2 shrink-0" />
                          Settings
                        </.dropdown_menu_link_item>
                      </.dropdown_menu_content>
                    </.dropdown_menu>
                  <% end %>
                </div>

                <p class="text-xs text-gray-500 truncate mb-3">{lib.root_path}</p>

                <div class="flex flex-wrap gap-2 mb-3">
                  <.badge class="bg-violet-900/50 text-violet-300 border-violet-800 text-xs">{books} books</.badge>
                  <.badge class="bg-violet-900/50 text-violet-300 border-violet-800 text-xs">{issues} issues</.badge>
                  <.badge class="bg-violet-900/50 text-violet-300 border-violet-800 text-xs">{series} series</.badge>
                  <%= if total_size > 0 do %>
                    <.badge variant="outline" class="bg-gray-800 text-gray-400 border-gray-700 text-xs">{Stashix.Formatters.format_bytes(total_size)}</.badge>
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
                    <.progress
                      value={if collecting, do: 100, else: pct}
                      indeterminate={false}
                      class={"h-1 bg-gray-800 #{cond do progress.done -> "[&>div]:bg-green-500"; collecting -> "[&>div]:bg-violet-500 [&>div]:animate-pulse"; true -> "[&>div]:bg-violet-500" end}"}
                    />
                  </div>
                <% end %>

                <a href={~p"/library/#{lib.id}"} class="text-sm text-violet-400 hover:text-violet-300">
                  Browse collection →
                </a>
              </.card_content>
            </.card>
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
                    book.type == "issue" && book.issue_number -> "Issue ##{book.issue_number}"
                    book.type == "issue" -> "Issue"
                    true -> "Standalone"
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
              Up Next
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
 
      <%!-- Per-library recent additions --%>
      <%= for %{library: lib, recent_books: books, recent_series: series, recent_issues: issues} <- @libraries_data do %>

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
                  title={book.title}
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
