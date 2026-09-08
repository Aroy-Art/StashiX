defmodule StashixWeb.HomeLive do
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
       full_bleed: true,
       libraries_data: libraries_data,
       continue_reading: continue_reading,
       next_issue: next_issue,
       scan_progress: %{},
       total_books: total_books,
       total_issues: total_issues,
       total_series: total_series,
       spotlight: pick_spotlight(libraries_data, continue_reading),
       recommendations: pick_recommendations(libraries_data)
     )}
  end

  defp pick_spotlight(_libraries_data, [_ | _]), do: nil

  defp pick_spotlight(libraries_data, []) do
    all_books = Enum.flat_map(libraries_data, & &1.recent_books)
    all_series = Enum.flat_map(libraries_data, & &1.recent_series)

    candidates =
      Enum.map(all_books, &{:book, &1}) ++ Enum.map(all_series, &{:series, &1})

    case candidates do
      [] ->
        nil

      _ ->
        case Enum.random(candidates) do
          {:book, book} -> {:book, Stashix.Repo.preload(book, :series)}
          other -> other
        end
    end
  end

  defp pick_recommendations(libraries_data) do
    books =
      libraries_data
      |> Enum.flat_map(& &1.recent_books)
      |> Enum.shuffle()
      |> Enum.take(2)
      |> Stashix.Repo.preload(:series)

    series =
      libraries_data
      |> Enum.flat_map(& &1.recent_series)
      |> Enum.shuffle()
      |> Enum.take(2)

    %{books: books, series: series}
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
  def handle_info(
        {:scan_progress, %{library_id: lib_id, scanned: scanned, total: total, done: done}},
        socket
      ) do
    socket =
      update(
        socket,
        :scan_progress,
        &Map.put(&1, lib_id, %{scanned: scanned, total: total, done: done})
      )

    if done do
      Process.send_after(self(), {:clear_scan_progress, lib_id}, 3_000)
    end

    {:noreply, socket}
  end

  def handle_info({:scan_progress, %{library_id: lib_id, scanned: scanned, total: total}}, socket) do
    {:noreply,
     update(
       socket,
       :scan_progress,
       &Map.put(&1, lib_id, %{scanned: scanned, total: total, done: false})
     )}
  end

  def handle_info({:clear_scan_progress, lib_id}, socket) do
    {:noreply, update(socket, :scan_progress, &Map.delete(&1, lib_id))}
  end

  def handle_info({:book_added, _book}, socket) do
    user = socket.assigns.current_user
    libraries = Library.list_libraries(user)
    libraries_data = Enum.map(libraries, &load_library_data/1)
    continue_reading = Library.in_progress_books(user.id, 20)

    {:noreply,
     assign(socket,
       libraries_data: libraries_data,
       continue_reading: continue_reading,
       next_issue: Library.next_issue_books(user.id, 20),
       total_books: Library.count_all_books(type: "standalone"),
       total_issues: Library.count_all_books(type: "issue"),
       total_series: Library.count_all_series([]),
       spotlight: pick_spotlight(libraries_data, continue_reading),
       recommendations: pick_recommendations(libraries_data)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%!-- HERO: random spotlight when no reading in progress --%>
      <%= if @continue_reading == [] && @spotlight != nil do %>
        <% {spotlight_type, spotlight_item} = @spotlight %>
        <div
          class="relative flex items-center gap-4 sm:gap-8 px-4 sm:px-8 py-5 sm:py-7 overflow-hidden"
          style="min-height:200px"
        >
          <div
            class="absolute inset-0"
            style="background:linear-gradient(130deg,rgba(76,29,149,0.55) 0%,transparent 65%)"
          >
          </div>
          <div
            class="absolute inset-0"
            style="background:radial-gradient(ellipse at 16% 55%,rgba(124,92,245,0.2) 0%,transparent 54%)"
          >
          </div>
          <div
            class="absolute inset-x-0 bottom-0 h-14"
            style="background:linear-gradient(to top,#030712,transparent)"
          >
          </div>

          <%= if spotlight_type == :book do %>
            <a
              href={~p"/book/#{spotlight_item.id}"}
              class="relative z-10 flex-shrink-0 rounded-md overflow-hidden shadow-[0_20px_50px_rgba(0,0,0,0.75)] hover:scale-[1.02] transition-transform duration-200"
              style="width:104px;height:156px;background:#1a1040"
            >
              <img
                src={~p"/api/books/#{spotlight_item.id}/cover?w=300"}
                class="w-full h-full object-cover"
                onerror="this.style.display='none'"
              />
            </a>
            <div class="relative z-10 flex flex-col gap-2 min-w-0 flex-1">
              <p class="text-[10px] sm:text-xs font-semibold tracking-widest uppercase text-violet-400 truncate">
                Discover<%= if spotlight_item.series do %>
                  ·
                  <a
                    href={~p"/series/#{spotlight_item.series.id}"}
                    class="hover:text-violet-300 transition-colors"
                  >{spotlight_item.series.name}</a>
                <% end %>
              </p>
              <h1
                class="text-lg sm:text-[1.6rem] font-bold text-white leading-tight"
                style="letter-spacing:-0.3px;text-wrap:balance"
              >
                {if spotlight_item.issue_number,
                  do: "##{spotlight_item.issue_number} – #{spotlight_item.title}",
                  else: spotlight_item.title}
              </h1>
              <p class="text-xs sm:text-sm text-gray-400">
                {if spotlight_item.page_count, do: "#{spotlight_item.page_count} pages", else: ""}
              </p>
              <div class="flex gap-2 mt-1">
                <a
                  href={~p"/read/#{spotlight_item.id}"}
                  class="flex items-center gap-1.5 px-3 sm:px-4 py-2 bg-violet-600 hover:bg-violet-500 text-white text-sm font-semibold rounded-md transition-colors"
                >
                  <svg class="w-3 h-3 fill-current" viewBox="0 0 24 24"><polygon points="5 3 19 12 5 21 5 3" /></svg>
                  Start Reading
                </a>
                <a
                  href={~p"/book/#{spotlight_item.id}"}
                  class="flex items-center px-3 sm:px-4 py-2 bg-gray-800/80 hover:bg-gray-700 text-gray-300 hover:text-white text-sm font-semibold rounded-md border border-gray-700 hover:border-gray-600 transition-colors"
                >
                  Details
                </a>
              </div>
            </div>
          <% else %>
            <a
              href={~p"/series/#{spotlight_item.id}"}
              class="relative z-10 flex-shrink-0 rounded-md overflow-hidden shadow-[0_20px_50px_rgba(0,0,0,0.75)] hover:scale-[1.02] transition-transform duration-200"
              style="width:104px;height:156px;background:#1a1040"
            >
              <img
                src={~p"/api/series/#{spotlight_item.id}/cover?w=300"}
                class="w-full h-full object-cover"
                onerror="this.style.display='none'"
              />
            </a>
            <div class="relative z-10 flex flex-col gap-2 min-w-0 flex-1">
              <p class="text-[10px] sm:text-xs font-semibold tracking-widest uppercase text-violet-400 truncate">
                Discover · Series
              </p>
              <h1
                class="text-lg sm:text-[1.6rem] font-bold text-white leading-tight"
                style="letter-spacing:-0.3px;text-wrap:balance"
              >
                {spotlight_item.name}
              </h1>
              <p class="text-xs sm:text-sm text-gray-400">
                {[
                  "#{spotlight_item.issue_count} issues",
                  series_date_range(spotlight_item)
                ]
                |> Enum.reject(&is_nil/1)
                |> Enum.join(" · ")}
              </p>
              <div class="flex gap-2 mt-1">
                <a
                  href={~p"/series/#{spotlight_item.id}"}
                  class="flex items-center gap-1.5 px-3 sm:px-4 py-2 bg-violet-600 hover:bg-violet-500 text-white text-sm font-semibold rounded-md transition-colors"
                >
                  Browse Series
                </a>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- HERO: cinematic spotlight on what you're reading --%>
      <%= if @continue_reading != [] do %>
        <% %{book: hero, current_page: hero_page} = hd(@continue_reading) %>
        <% hero_pct =
          if hero.page_count && hero.page_count > 1,
            do: round(min(hero_page / (hero.page_count - 1), 1.0) * 100),
            else: nil %>
        <div
          class="relative flex items-center gap-4 sm:gap-8 px-4 sm:px-8 py-5 sm:py-7 overflow-hidden"
          style="min-height:200px"
        >
          <div
            class="absolute inset-0"
            style="background:linear-gradient(130deg,rgba(76,29,149,0.55) 0%,transparent 65%)"
          >
          </div>
          <div
            class="absolute inset-0"
            style="background:radial-gradient(ellipse at 16% 55%,rgba(124,92,245,0.2) 0%,transparent 54%)"
          >
          </div>
          <div
            class="absolute inset-x-0 bottom-0 h-14"
            style="background:linear-gradient(to top,#030712,transparent)"
          >
          </div>

          <a
            href={~p"/book/#{hero.id}"}
            class="relative z-10 flex-shrink-0 rounded-md overflow-hidden shadow-[0_20px_50px_rgba(0,0,0,0.75)] hover:scale-[1.02] transition-transform duration-200"
            style="width:104px;height:156px;background:#1a1040"
          >
            <img
              src={~p"/api/books/#{hero.id}/cover?w=300"}
              class="w-full h-full object-cover"
              onerror="this.style.display='none'"
            />
          </a>

          <div class="relative z-10 flex flex-col gap-2 min-w-0 flex-1">
            <p class="text-[10px] sm:text-xs font-semibold tracking-widest uppercase text-violet-400 truncate">
              Continue Reading<%= if hero.series do %>
                ·
                <a
                  href={~p"/series/#{hero.series.id}"}
                  class="hover:text-violet-300 transition-colors"
                >{hero.series.name}</a>
              <% end %>
            </p>
            <h1
              class="text-lg sm:text-[1.6rem] font-bold text-white leading-tight"
              style="letter-spacing:-0.3px;text-wrap:balance"
            >
              {if hero.issue_number, do: "##{hero.issue_number} – #{hero.title}", else: hero.title}
            </h1>
            <p class="text-xs sm:text-sm text-gray-400">
              {cond do
                hero.type == "issue" && hero.issue_number && hero.series ->
                  "Issue #{hero.issue_number} of #{hero.series.issue_count} · #{if hero.page_count, do: "#{hero.page_count} pages", else: ""}"

                hero.type == "issue" && hero.issue_number ->
                  "Issue ##{hero.issue_number}"

                hero.page_count ->
                  "#{hero.page_count} pages"

                true ->
                  ""
              end}
            </p>
            <%= if hero_pct do %>
              <div class="flex items-center gap-3">
                <div class="w-32 sm:w-44 h-0.5 bg-gray-700 rounded-full overflow-hidden">
                  <div class="h-full bg-violet-500 rounded-full" style={"width:#{hero_pct}%"}></div>
                </div>
                <span class="text-xs text-gray-500">{hero_pct}%</span>
              </div>
            <% end %>
            <div class="flex gap-2 mt-1">
              <a
                href={~p"/read/#{hero.id}"}
                class="flex items-center gap-1.5 px-3 sm:px-4 py-2 bg-violet-600 hover:bg-violet-500 text-white text-sm font-semibold rounded-md transition-colors"
              >
                <svg class="w-3 h-3 fill-current" viewBox="0 0 24 24"><polygon points="5 3 19 12 5 21 5 3" /></svg> Continue
              </a>
              <a
                href={~p"/book/#{hero.id}"}
                class="flex items-center px-3 sm:px-4 py-2 bg-gray-800/80 hover:bg-gray-700 text-gray-300 hover:text-white text-sm font-semibold rounded-md border border-gray-700 hover:border-gray-600 transition-colors"
              >
                Details
              </a>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- STAT STRIP --%>
      <div class="flex items-center px-4 sm:px-8 py-2.5 border-b border-gray-800 bg-gray-900/50">
        <a
          href={~p"/books"}
          class="flex items-baseline gap-1.5 pr-5 mr-5 border-r border-gray-800 hover:text-violet-400 transition-colors group"
        >
          <span class="text-[1.1rem] font-bold text-white group-hover:text-violet-400 transition-colors">{@total_books}</span>
          <span class="text-xs text-gray-500">Books</span>
        </a>
        <a
          href={~p"/series"}
          class="flex items-baseline gap-1.5 pr-5 mr-5 border-r border-gray-800 hover:text-violet-400 transition-colors group"
        >
          <span class="text-[1.1rem] font-bold text-white group-hover:text-violet-400 transition-colors">{@total_series}</span>
          <span class="text-xs text-gray-500">Series</span>
        </a>
        <a
          href={~p"/issues"}
          class="flex items-baseline gap-1.5 hover:text-violet-400 transition-colors group"
        >
          <span class="text-[1.1rem] font-bold text-white group-hover:text-violet-400 transition-colors">{@total_issues}</span>
          <span class="text-xs text-gray-500">Issues</span>
        </a>
      </div>

      <%!-- TWO-COLUMN BODY --%>
      <div class="flex flex-col lg:flex-row gap-5 p-4 lg:p-6 lg:items-start">
        <%!-- Left column: reading queue + up next --%>
        <div class="flex-1 min-w-0 flex flex-col gap-5">
          <%!-- Continue Reading (secondary items — hero covers the first) --%>
          <%= if length(@continue_reading) > 1 do %>
            <section>
              <h2 class="text-sm font-semibold text-white mb-3 flex items-center gap-2">
                <span class="w-0.5 h-4 bg-violet-500 rounded-full inline-block"></span> Also Reading
              </h2>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                <%= for %{book: book, current_page: current_page} <- Enum.drop(@continue_reading, 1) do %>
                  <% pct =
                    if book.page_count && book.page_count > 1,
                      do: round(min(current_page / (book.page_count - 1), 1.0) * 100),
                      else: nil %>
                  <a
                    href={~p"/book/#{book.id}"}
                    class="group flex gap-3 p-3 rounded-lg bg-gray-900 border border-gray-800 hover:border-violet-700/50 transition-colors"
                  >
                    <div class="w-12 h-[72px] rounded flex-shrink-0 overflow-hidden bg-gray-800">
                      <img
                        src={~p"/api/books/#{book.id}/cover?w=120"}
                        class="w-full h-full object-cover"
                        onerror="this.style.display='none'"
                      />
                    </div>
                    <div class="flex-1 min-w-0 flex flex-col justify-center gap-1">
                      <%= if book.series do %>
                        <p class="text-[10px] font-semibold tracking-wide uppercase text-violet-400">
                          {book.series.name}
                        </p>
                      <% end %>
                      <p class="text-sm font-semibold text-white leading-snug">
                        {if book.issue_number,
                          do: "##{book.issue_number} – #{book.title}",
                          else: book.title}
                      </p>
                      <%= if pct do %>
                        <div class="flex items-center gap-2">
                          <div class="flex-1 h-px bg-gray-700 rounded-full overflow-hidden">
                            <div class="h-full bg-violet-500 rounded-full" style={"width:#{pct}%"}></div>
                          </div>
                          <span class="text-[10px] text-gray-500">{pct}%</span>
                        </div>
                      <% end %>
                    </div>
                  </a>
                <% end %>
              </div>
            </section>
          <% end %>

          <%!-- Up Next --%>
          <%= if @next_issue != [] do %>
            <section>
              <div class="flex items-center justify-between mb-3">
                <h2 class="text-sm font-semibold text-white flex items-center gap-2">
                  <span class="w-0.5 h-4 bg-violet-500 rounded-full inline-block"></span> Up Next
                </h2>
                <a href={~p"/issues"} class="text-xs text-violet-400 hover:text-violet-300">See all →</a>
              </div>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                <%= for book <- Enum.take(@next_issue, 5) do %>
                  <a
                    href={~p"/book/#{book.id}"}
                    class="group flex gap-3 p-3 rounded-lg bg-gray-900 border border-gray-800 hover:border-violet-700/50 transition-colors"
                  >
                    <div class="w-12 h-[72px] rounded flex-shrink-0 overflow-hidden bg-gray-800">
                      <img
                        src={~p"/api/books/#{book.id}/cover?w=120"}
                        class="w-full h-full object-cover"
                        onerror="this.style.display='none'"
                      />
                    </div>
                    <div class="flex-1 min-w-0 flex flex-col justify-center gap-0.5">
                      <%= if book.series do %>
                        <p class="text-[10px] font-semibold tracking-wide uppercase text-violet-400">
                          {book.series.name}
                        </p>
                      <% end %>
                      <p class="text-sm font-semibold text-white leading-snug">
                        {if book.issue_number,
                          do: "##{book.issue_number} – #{book.title}",
                          else: book.title}
                      </p>
                      <p class="text-xs text-gray-500">
                        {cond do
                          book.type == "issue" && book.issue_number && book.series ->
                            "Issue #{book.issue_number} of #{book.series.issue_count}"

                          book.issue_number ->
                            "Issue ##{book.issue_number}"

                          true ->
                            ""
                        end}
                      </p>
                    </div>
                    <div class="flex-shrink-0 self-center">
                      <span class="text-[10px] font-semibold px-2 py-0.5 rounded bg-violet-900/40 text-violet-300 border border-violet-800/40">Next</span>
                    </div>
                  </a>
                <% end %>
              </div>
            </section>
          <% end %>

          <%!-- Recommendations when nothing in progress or queued --%>
          <%= if @continue_reading == [] && @next_issue == [] do %>
            <% rec_books = @recommendations.books %>
            <% rec_series = @recommendations.series %>
            <%= if rec_books != [] || rec_series != [] do %>
              <section>
                <h2 class="text-sm font-semibold text-white mb-3 flex items-center gap-2">
                  <span class="w-0.5 h-4 bg-violet-500 rounded-full inline-block"></span> Start Reading
                </h2>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <%= for book <- rec_books do %>
                    <div class="flex gap-3 p-3 rounded-lg bg-gray-900 border border-gray-800 hover:border-violet-700/50 transition-colors">
                      <a
                        href={~p"/book/#{book.id}"}
                        class="w-16 h-24 rounded flex-shrink-0 overflow-hidden bg-gray-800 hover:scale-[1.02] transition-transform duration-200"
                      >
                        <img
                          src={~p"/api/books/#{book.id}/cover?w=160"}
                          class="w-full h-full object-cover"
                          onerror="this.style.display='none'"
                        />
                      </a>
                      <div class="flex-1 min-w-0 flex flex-col justify-center gap-1.5">
                        <%= if book.series && !is_struct(book.series, Ecto.Association.NotLoaded) do %>
                          <p class="text-[10px] font-semibold tracking-wide uppercase text-violet-400 truncate">
                            {book.series.name}
                          </p>
                        <% end %>
                        <p class="text-sm font-semibold text-white leading-snug">
                          {if book.issue_number,
                            do: "##{book.issue_number} – #{book.title}",
                            else: book.title}
                        </p>
                        <p class="text-xs text-gray-500">
                          {[book.year && to_string(book.year), book.page_count && "#{book.page_count} pages"]
                          |> Enum.reject(&is_nil/1)
                          |> Enum.join(" · ")}
                        </p>
                        <a
                          href={~p"/read/#{book.id}"}
                          class="mt-0.5 self-start flex items-center gap-1 px-2.5 py-1 bg-violet-700/60 hover:bg-violet-600 text-violet-200 hover:text-white text-xs font-semibold rounded transition-colors"
                        >
                          <svg class="w-2.5 h-2.5 fill-current" viewBox="0 0 24 24"><polygon points="5 3 19 12 5 21 5 3" /></svg>
                          Read
                        </a>
                      </div>
                    </div>
                  <% end %>
                  <%= for s <- rec_series do %>
                    <div class="flex gap-3 p-3 rounded-lg bg-gray-900 border border-gray-800 hover:border-violet-700/50 transition-colors">
                      <a
                        href={~p"/series/#{s.id}"}
                        class="w-16 h-24 rounded flex-shrink-0 overflow-hidden bg-gray-800 hover:scale-[1.02] transition-transform duration-200"
                      >
                        <img
                          src={~p"/api/series/#{s.id}/cover?w=160"}
                          class="w-full h-full object-cover"
                          onerror="this.style.display='none'"
                        />
                      </a>
                      <div class="flex-1 min-w-0 flex flex-col justify-center gap-1.5">
                        <p class="text-[10px] font-semibold tracking-wide uppercase text-violet-400 truncate">
                          Series
                        </p>
                        <p class="text-sm font-semibold text-white leading-snug">{s.name}</p>
                        <p class="text-xs text-gray-500">
                          {[
                            "#{s.issue_count} issues",
                            series_date_range(s)
                          ]
                          |> Enum.reject(&is_nil/1)
                          |> Enum.join(" · ")}
                        </p>
                        <a
                          href={~p"/series/#{s.id}"}
                          class="mt-0.5 self-start px-2.5 py-1 bg-violet-700/60 hover:bg-violet-600 text-violet-200 hover:text-white text-xs font-semibold rounded transition-colors"
                        >
                          Browse
                        </a>
                      </div>
                    </div>
                  <% end %>
                </div>
              </section>
            <% end %>
          <% end %>
        </div>

        <%!-- Right column: libraries --%>
        <div class="w-full lg:w-60 lg:flex-shrink-0 flex flex-col gap-3">
          <h2 class="text-sm font-semibold text-white flex items-center gap-2">
            <span class="w-0.5 h-4 bg-violet-500 rounded-full inline-block"></span> Libraries
          </h2>
          <div class="grid grid-cols-2 lg:grid-cols-1 gap-3">
            <%= for %{library: lib, book_count: books, series_count: series, issue_count: issues, total_size: total_size, cover_books: covers} <- @libraries_data do %>
              <div class="rounded-lg bg-gray-900 border border-gray-800 overflow-hidden hover:border-gray-700 transition-colors">
                <div class="flex h-14 overflow-hidden relative bg-gray-800">
                  <%= for book <- Enum.take(covers, 5) do %>
                    <div class="flex-1 min-w-0">
                      <img
                        src={~p"/api/books/#{book.id}/cover?w=80"}
                        class="w-full h-full object-cover"
                        onerror="this.style.display='none'"
                      />
                    </div>
                  <% end %>
                  <div class="absolute inset-0 bg-gradient-to-t from-gray-900/60 to-transparent"></div>
                </div>
                <div class="p-3">
                  <div class="flex items-center justify-between mb-2">
                    <h3 class="text-sm font-semibold text-white">{lib.name}</h3>
                    <%= if @current_user.role == :admin do %>
                      <.dropdown_menu id={"home-lib-menu-#{lib.id}"}>
                        <.dropdown_menu_trigger class="p-1 rounded text-gray-500 hover:text-white hover:bg-gray-700 transition-all ml-1 flex-shrink-0">
                          <.icon name="lucide-ellipsis-vertical" class="w-3 h-3" />
                        </.dropdown_menu_trigger>
                        <.dropdown_menu_content
                          align="end"
                          class="bg-gray-800 border-gray-700 text-gray-300 whitespace-nowrap"
                        >
                          <.dropdown_menu_item
                            class="hover:bg-gray-700 focus:bg-gray-700 cursor-pointer"
                            on-select={JS.push("sidebar_scan", value: %{id: lib.id})}
                          >
                            <.icon name="lucide-refresh-cw" class="w-3.5 h-3.5 mr-2 shrink-0" /> Scan for new files
                          </.dropdown_menu_item>
                          <.dropdown_menu_item
                            class="hover:bg-gray-700 focus:bg-gray-700 cursor-pointer"
                            on-select={JS.push("sidebar_force_scan", value: %{id: lib.id})}
                          >
                            <.icon name="lucide-rotate-ccw" class="w-3.5 h-3.5 mr-2 shrink-0" /> Force rescan
                          </.dropdown_menu_item>
                          <.dropdown_menu_separator class="bg-gray-700" />
                          <.dropdown_menu_link_item
                            href="/admin"
                            class="hover:bg-gray-700 focus:bg-gray-700"
                          >
                            <.icon name="lucide-settings" class="w-3.5 h-3.5 mr-2 shrink-0" /> Settings
                          </.dropdown_menu_link_item>
                        </.dropdown_menu_content>
                      </.dropdown_menu>
                    <% end %>
                  </div>
                  <div class="flex flex-wrap gap-1.5 mb-2.5">
                    <span class="text-[10px] bg-violet-900/40 text-violet-300 border border-violet-800/40 rounded px-1.5 py-0.5">{books} books</span>
                    <span class="text-[10px] bg-violet-900/40 text-violet-300 border border-violet-800/40 rounded px-1.5 py-0.5">{issues} issues</span>
                    <span class="text-[10px] bg-violet-900/40 text-violet-300 border border-violet-800/40 rounded px-1.5 py-0.5">{series} series</span>
                    <%= if total_size > 0 do %>
                      <span class="text-[10px] bg-gray-800 text-gray-400 border border-gray-700 rounded px-1.5 py-0.5">{Stashix.Formatters.format_bytes(
                        total_size
                      )}</span>
                    <% end %>
                  </div>
                  <%= if progress = @scan_progress[lib.id] do %>
                    <% collecting = progress.total == 0 and not progress.done

                    label =
                      cond do
                        progress.done -> "Complete"
                        collecting -> "Collecting files..."
                        true -> "Scanning..."
                      end

                    pct =
                      if progress.total > 0,
                        do: round(progress.scanned / progress.total * 100),
                        else: 0 %>
                    <div class={"mb-2 transition-opacity duration-1000 #{if progress.done, do: "opacity-0", else: "opacity-100"}"}>
                      <div class="flex justify-between text-[10px] text-gray-500 mb-1">
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
                  <a
                    href={~p"/library/#{lib.id}"}
                    class="text-xs text-violet-400 hover:text-violet-300"
                  >Browse collection →</a>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- RECENTLY ADDED SHELF --%>
      <% recent_books = @libraries_data |> Enum.flat_map(& &1.recent_books) %>
      <% recent_series = @libraries_data |> Enum.flat_map(& &1.recent_series) %>
      <% recent_issues = @libraries_data |> Enum.flat_map(& &1.recent_issues) %>

      <%= if recent_books != [] do %>
        <section class="px-4 sm:px-6 pb-6">
          <div class="flex items-center justify-between mb-3">
            <h2 class="text-sm font-semibold text-white flex items-center gap-2">
              <span class="w-0.5 h-4 bg-violet-500 rounded-full inline-block"></span> Recent Books
            </h2>
            <div class="flex gap-1">
              <button
                onclick="document.getElementById('home-recent-books').scrollBy({left:-500,behavior:'smooth'})"
                class="p-1 rounded text-gray-500 hover:text-white hover:bg-gray-800"
              >
                <.icon name="lucide-chevron-left" class="w-4 h-4" />
              </button>
              <button
                onclick="document.getElementById('home-recent-books').scrollBy({left:500,behavior:'smooth'})"
                class="p-1 rounded text-gray-500 hover:text-white hover:bg-gray-800"
              >
                <.icon name="lucide-chevron-right" class="w-4 h-4" />
              </button>
            </div>
          </div>
          <div id="home-recent-books" class="flex gap-3 overflow-x-auto pb-2 scrollbar-hide">
            <%= for book <- recent_books do %>
              <.media_card
                href={~p"/book/#{book.id}"}
                title={book.title}
                cover_url={~p"/api/books/#{book.id}/cover"}
                width={288}
                subtitle={book.year && to_string(book.year)}
                page_count={book.page_count}
                type={:book}
                blurhash={book.cover && book.cover.blurhash}
                class="flex-shrink-0 w-32"
              />
            <% end %>
          </div>
        </section>
      <% end %>

      <%= if recent_series != [] do %>
        <section class="px-4 sm:px-6 pb-6">
          <div class="flex items-center justify-between mb-3">
            <h2 class="text-sm font-semibold text-white flex items-center gap-2">
              <span class="w-0.5 h-4 bg-violet-500 rounded-full inline-block"></span> Recent Series
            </h2>
            <div class="flex gap-1">
              <button
                onclick="document.getElementById('home-recent-series').scrollBy({left:-500,behavior:'smooth'})"
                class="p-1 rounded text-gray-500 hover:text-white hover:bg-gray-800"
              >
                <.icon name="lucide-chevron-left" class="w-4 h-4" />
              </button>
              <button
                onclick="document.getElementById('home-recent-series').scrollBy({left:500,behavior:'smooth'})"
                class="p-1 rounded text-gray-500 hover:text-white hover:bg-gray-800"
              >
                <.icon name="lucide-chevron-right" class="w-4 h-4" />
              </button>
            </div>
          </div>
          <div id="home-recent-series" class="flex gap-3 overflow-x-auto pb-2 scrollbar-hide">
            <%= for s <- recent_series do %>
              <.media_card
                href={~p"/series/#{s.id}"}
                title={s.name}
                cover_url={~p"/api/series/#{s.id}/cover"}
                width={288}
                subtitle={series_date_range(s)}
                badge={"#{s.issue_count} issues"}
                type={:series}
                blurhash={s.cover_blurhash}
                class="flex-shrink-0 w-32"
              />
            <% end %>
          </div>
        </section>
      <% end %>

      <%= if recent_issues != [] do %>
        <section class="px-4 sm:px-6 pb-8">
          <div class="flex items-center justify-between mb-3">
            <h2 class="text-sm font-semibold text-white flex items-center gap-2">
              <span class="w-0.5 h-4 bg-violet-500 rounded-full inline-block"></span> Recent Issues
            </h2>
            <div class="flex gap-1">
              <button
                onclick="document.getElementById('home-recent-issues').scrollBy({left:-500,behavior:'smooth'})"
                class="p-1 rounded text-gray-500 hover:text-white hover:bg-gray-800"
              >
                <.icon name="lucide-chevron-left" class="w-4 h-4" />
              </button>
              <button
                onclick="document.getElementById('home-recent-issues').scrollBy({left:500,behavior:'smooth'})"
                class="p-1 rounded text-gray-500 hover:text-white hover:bg-gray-800"
              >
                <.icon name="lucide-chevron-right" class="w-4 h-4" />
              </button>
            </div>
          </div>
          <div id="home-recent-issues" class="flex gap-3 overflow-x-auto pb-2 scrollbar-hide">
            <%= for book <- recent_issues do %>
              <.media_card
                href={~p"/book/#{book.id}"}
                title={book.title}
                cover_url={~p"/api/books/#{book.id}/cover"}
                width={288}
                subtitle={book.year && to_string(book.year)}
                badge={
                  cond do
                    book.volume && book.issue_number -> "Vol #{book.volume}  ##{book.issue_number}"
                    book.issue_number -> "##{book.issue_number}"
                    true -> nil
                  end
                }
                type={:book}
                blurhash={book.cover && book.cover.blurhash}
                class="flex-shrink-0 w-32"
              />
            <% end %>
          </div>
        </section>
      <% end %>
    </div>
    """
  end
end
