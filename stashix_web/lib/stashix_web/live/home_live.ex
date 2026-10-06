defmodule StashixWeb.HomeLive do
  use StashixWeb, :live_view

  import StashixWeb.CollectionComponents, only: [collection_card: 1]

  alias Stashix.Library

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    access = socket.assigns.access
    libraries = Library.list_libraries(user)

    libraries_data = Enum.map(libraries, &load_library_data(access, &1))
    continue_reading = Library.in_progress_books(access, user.id, 20)
    next_issue = Library.next_issue_books(access, user.id, 20)

    total_books = Library.count_all_books(access: access, type: "standalone")
    total_issues = Library.count_all_books(access: access, type: "issue")
    total_series = Library.count_all_series(access: access)

    {:ok,
     assign(socket,
       page_title: "Home",
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

  defp load_library_data(access, lib) do
    recent_standalone = Library.recent_books(access, lib.id, 20, "standalone")
    recent_issues = Library.recent_issues(access, lib.id, 20)
    cover_books = Enum.take(recent_standalone ++ recent_issues, 5)

    %{
      library: lib,
      book_count: Library.count_books(access, lib.id),
      series_count: Library.count_series(access, lib.id),
      issue_count: Library.count_issues(access, lib.id),
      total_size: Library.total_size(access, lib.id),
      cover_books: cover_books,
      recent_books: recent_standalone,
      recent_series: Library.recent_series(access, lib.id, 20),
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
    access = socket.assigns.access
    libraries = Library.list_libraries(user)
    libraries_data = Enum.map(libraries, &load_library_data(access, &1))
    continue_reading = Library.in_progress_books(access, user.id, 20)

    {:noreply,
     assign(socket,
       libraries_data: libraries_data,
       continue_reading: continue_reading,
       next_issue: Library.next_issue_books(access, user.id, 20),
       total_books: Library.count_all_books(access: access, type: "standalone"),
       total_issues: Library.count_all_books(access: access, type: "issue"),
       total_series: Library.count_all_series(access: access),
       spotlight: pick_spotlight(libraries_data, continue_reading),
       recommendations: pick_recommendations(libraries_data)
     )}
  end

  def handle_info({:cover_updated, _}, socket), do: {:noreply, socket}

  # What the hero shows: the book being read, else a random pick, else nothing.
  defp hero(%{continue_reading: [%{book: book, current_page: page} | _]}) do
    series = loaded(book.series)
    count = series && Map.get(series, :issue_count)

    %{
      id: "home-hero-#{book.id}",
      eyebrow: "Continue reading",
      series: series,
      sticker: book.issue_number && "##{book.issue_number}",
      ghost: book.issue_number && to_string(book.issue_number),
      title: book.title,
      meta:
        Enum.reject(
          [
            book.issue_number && count && count > 0 && "Issue #{book.issue_number} of #{count}",
            book.page_count && book.page_count > 0 && "Page #{page + 1} of #{book.page_count}"
          ],
          &(&1 in [nil, false])
        ),
      progress: if(book.page_count && book.page_count > 1, do: min(page / (book.page_count - 1), 1.0)),
      cover: ~p"/api/books/#{book.id}/cover",
      to: ~p"/book/#{book.id}",
      primary: {"Continue", "lucide-play", ~p"/read/#{book.id}"},
      secondary: {"Details", ~p"/book/#{book.id}"}
    }
  end

  defp hero(%{spotlight: {:book, book}}) do
    %{
      id: "home-hero-#{book.id}",
      eyebrow: "Discover",
      series: loaded(book.series),
      sticker: book.issue_number && "##{book.issue_number}",
      ghost: book.issue_number && to_string(book.issue_number),
      title: book.title,
      meta: if(book.page_count && book.page_count > 0, do: ["#{book.page_count} pages"], else: []),
      progress: nil,
      cover: ~p"/api/books/#{book.id}/cover",
      to: ~p"/book/#{book.id}",
      primary: {"Start reading", "lucide-play", ~p"/read/#{book.id}"},
      secondary: {"Details", ~p"/book/#{book.id}"}
    }
  end

  defp hero(%{spotlight: {:series, series}}) do
    %{
      id: "home-hero-#{series.id}",
      eyebrow: "Discover a series",
      series: nil,
      sticker: nil,
      ghost: series.issue_count && series.issue_count > 1 && to_string(series.issue_count),
      title: series.name,
      meta:
        Enum.reject(
          [series.issue_count && "#{series.issue_count} issues", Stashix.Formatters.series_years(series)],
          &is_nil/1
        ),
      progress: nil,
      cover: ~p"/api/series/#{series.id}/cover",
      to: ~p"/series/#{series.id}",
      primary: {"Browse series", "lucide-library", ~p"/series/#{series.id}"},
      secondary: nil
    }
  end

  defp hero(_assigns), do: nil

  defp loaded(%Ecto.Association.NotLoaded{}), do: nil
  defp loaded(other), do: other

  attr :hero, :map, required: true

  defp home_hero(assigns) do
    ~H"""
    <header class="relative flex flex-col items-center sm:flex-row sm:items-end gap-7 sm:gap-12 pt-2">
      <.ghost_numeral :if={@hero.ghost} class="hidden sm:block absolute -top-4 right-0 text-[11rem] md:text-[14rem]">
        {@hero.ghost}
      </.ghost_numeral>

      <.link
        navigate={@hero.to}
        aria-label={@hero.title}
        class="rise relative block w-36 sm:w-44 flex-shrink-0 aspect-[2/3] rounded-md overflow-hidden bg-gray-800 ring-1 ring-white/15 shadow-[0_24px_60px_-12px_rgba(0,0,0,0.9)] -rotate-2 hover:rotate-0 transition-transform duration-300"
      >
        <img
          src={"#{@hero.cover}?s=l"}
          alt=""
          class="w-full h-full object-cover"
          onerror="this.style.display='none'"
          draggable="false"
        />
      </.link>

      <div class="relative min-w-0 flex-1 text-center sm:text-left sm:pb-1">
        <div class="rise flex items-center justify-center sm:justify-start flex-wrap gap-x-3 gap-y-2 mb-3" style="--i:1">
          <.sticker :if={@hero.sticker} size="lg">{@hero.sticker}</.sticker>
          <.eyebrow>
            {@hero.eyebrow}
            <span :if={@hero.series} class="text-white/25"> / </span>
            <.link
              :if={@hero.series}
              navigate={~p"/series/#{@hero.series.id}"}
              class="hover:text-white transition-colors"
            >
              {@hero.series.name}
            </.link>
          </.eyebrow>
        </div>

        <.display_heading level={1} size="hero" class="rise" style="--i:2">{@hero.title}</.display_heading>

        <p
          :if={@hero.meta != []}
          class="rise flex items-center justify-center sm:justify-start flex-wrap gap-x-3 gap-y-1 mt-4 text-sm text-gray-300 tabular-nums"
          style="--i:3"
        >
          <span :for={part <- @hero.meta}>{part}</span>
        </p>
        <.progress_bar
          :if={@hero.progress}
          value={@hero.progress}
          label="Reading progress"
          class="rise h-1.5 mt-3 mx-auto sm:mx-0 max-w-xs"
          style="--i:3"
        />

        <div class="rise flex items-center justify-center sm:justify-start flex-wrap gap-4 mt-7" style="--i:4">
          <% {label, icon, to} = @hero.primary %>
          <.ink_button navigate={to}><.icon name={icon} class="w-4 h-4" /> {label}</.ink_button>
          <.ink_button :if={@hero.secondary} variant="ghost" navigate={elem(@hero.secondary, 1)}>
            {elem(@hero.secondary, 0)}
          </.ink_button>
        </div>
      </div>
    </header>
    """
  end

  @impl true
  def render(assigns) do
    picks? =
      (assigns.next_issue == [] or length(assigns.continue_reading) <= 1) and
        (assigns.recommendations.books != [] or assigns.recommendations.series != [])

    assigns =
      assign(assigns,
        hero: hero(assigns),
        recent_series: Enum.flat_map(assigns.libraries_data, & &1.recent_series),
        recent_books: Enum.flat_map(assigns.libraries_data, & &1.recent_books),
        recent_issues: Enum.flat_map(assigns.libraries_data, & &1.recent_issues),
        picks?: picks?,
        queues?: picks? or length(assigns.continue_reading) > 1 or assigns.next_issue != []
      )

    ~H"""
    <.page wide cover_src={@hero && "#{@hero.cover}?s=s"}>
      <.home_hero :if={@hero} hero={@hero} />

      <.page_hero :if={!@hero} title="Your stash" eyebrow="Welcome" />
      <.empty_state :if={!@hero} ghost="0" title="Nothing on the shelves yet">
        Add a library and scan it, and what you can read shows up here.
        <:actions :if={@current_user.role == :admin}>
          <.ink_button navigate={~p"/admin/libraries"}><.icon name="lucide-folder-plus" class="w-4 h-4" /> Add a library</.ink_button>
        </:actions>
      </.empty_state>

      <.panel :if={@hero} variant="indicia">
        <.stat_list class="px-6 py-5">
          <.stat label="Series" navigate={~p"/series"}>{@total_series}</.stat>
          <.stat label="Books" navigate={~p"/books"}>{@total_books}</.stat>
          <.stat label="Issues" navigate={~p"/issues"}>{@total_issues}</.stat>
        </.stat_list>
      </.panel>

      <%!-- Reading queues on the left, libraries down the side (below on small screens) --%>
      <div class="flex flex-col lg:flex-row lg:items-start gap-8 lg:gap-10">
        <div :if={@queues?} class="flex-1 min-w-0 space-y-8">
          <%!-- The hero already shows the first book in progress --%>
          <.section :if={length(@continue_reading) > 1} title="Also reading" count={length(@continue_reading) - 1}>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
              <.book_row
                :for={%{book: book, current_page: page} <- Enum.drop(@continue_reading, 1)}
                book={book}
                read={page}
              />
            </div>
          </.section>

          <.section :if={@next_issue != []} title="Up next" count={length(@next_issue)}>
            <:actions :if={length(@next_issue) > 6}>
              <.text_link navigate={~p"/issues"}>
                See all <.icon name="lucide-arrow-right" class="w-4 h-4 text-ink" />
              </.text_link>
            </:actions>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
              <.book_row :for={book <- Enum.take(@next_issue, 6)} book={book} />
            </div>
          </.section>

          <.section :if={@picks?} title="Start reading">
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
              <.book_row :for={book <- @recommendations.books} book={book} />
              <.media_row
                :for={s <- @recommendations.series}
                navigate={~p"/series/#{s.id}"}
                title={s.name}
                cover_url={~p"/api/series/#{s.id}/cover"}
                eyebrow="Series"
                detail={
                  [s.issue_count && "#{s.issue_count} issues", Stashix.Formatters.series_years(s)]
                  |> Enum.filter(& &1)
                  |> Enum.join(" · ")
                }
              />
            </div>
          </.section>
        </div>

        <.section
          :if={@libraries_data != []}
          title="Libraries"
          count={length(@libraries_data)}
          class={if @queues?, do: "w-full lg:w-64 lg:flex-shrink-0", else: "w-full"}
        >
          <div class={[
            "grid gap-4",
            if(@queues?,
              do: "grid-cols-1 sm:grid-cols-2 lg:grid-cols-1",
              else: "grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-4"
            )
          ]}>
            <.collection_card
              :for={data <- @libraries_data}
              navigate={~p"/library/#{data.library.id}"}
              name={data.library.name}
              covers={for book <- Enum.take(data.cover_books, 5), do: ~p"/api/books/#{book.id}/cover?s=sx"}
              stats={[{"series", data.series_count}, {"books", data.book_count}, {"issues", data.issue_count}]}
              note="Empty — scan it to fill it"
            >
              <:menu :if={@current_user.role == :admin}>
                <.library_menu id={"home-lib-menu-#{data.library.id}"} library_id={data.library.id} />
              </:menu>
              <p :if={data.total_size > 0} class="mt-1 text-xs text-gray-500 tabular-nums">
                {Stashix.Formatters.format_bytes(data.total_size)}
              </p>
              <.scan_status
                :if={@scan_progress[data.library.id]}
                progress={@scan_progress[data.library.id]}
                name={data.library.name}
              />
            </.collection_card>
          </div>
        </.section>
      </div>

      <.shelf :if={@recent_series != []} id="home-recent-series" title="Recent series">
        <.series_card :for={s <- @recent_series} series={s} scope="recent-series" class="flex-shrink-0 w-36" />
      </.shelf>

      <.shelf :if={@recent_books != []} id="home-recent-books" title="Recent books">
        <.book_card :for={book <- @recent_books} book={book} scope="recent-books" class="flex-shrink-0 w-36" />
      </.shelf>

      <.shelf :if={@recent_issues != []} id="home-recent-issues" title="Recent issues">
        <.book_card :for={book <- @recent_issues} book={book} as={:issue} scope="recent-issues" class="flex-shrink-0 w-36" />
      </.shelf>
    </.page>
    """
  end

  attr :progress, :map, required: true
  attr :name, :string, required: true

  # Scan progress inside a library card; fades out once the scan is done.
  defp scan_status(assigns) do
    progress = assigns.progress
    collecting = progress.total == 0 and not progress.done

    assigns =
      assign(assigns,
        collecting: collecting,
        label:
          cond do
            progress.done -> "Complete"
            collecting -> "Collecting files…"
            true -> "Scanning… #{progress.scanned}/#{progress.total}"
          end,
        value:
          cond do
            progress.done -> 1.0
            collecting -> nil
            true -> progress.scanned / progress.total
          end
      )

    ~H"""
    <div class={["mt-2.5 transition-opacity duration-1000", if(@progress.done, do: "opacity-0", else: "opacity-100")]}>
      <p class="mb-1 text-[10px] font-bold tracking-[0.14em] uppercase text-ink/80 tabular-nums">{@label}</p>
      <.run_bar value={@value} label={"#{@name} scan progress"} />
    </div>
    """
  end
end
