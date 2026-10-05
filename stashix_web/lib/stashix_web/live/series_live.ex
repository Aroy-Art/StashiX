defmodule StashixWeb.SeriesLive do
  use StashixWeb, :live_view

  alias Stashix.{Formatters, Library, Metadata, Scanner}
  alias Stashix.Library.Series
  alias Stashix.Metadata.Roles
  import StashixWeb.MetadataComponents
  import StashixWeb.DetailComponents
  import StashixWeb.DialogHistory

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @admin_events ~w(save_metadata fetch_metadata toggle_metadata_lock rescan_series force_rescan_series)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    series = Library.get_series_with_books(socket.assigns.access, id)
    library = Library.get_readable_library!(socket.assigns.access, series.library_id)

    total_pages = Enum.sum(Enum.map(series.books, & &1.page_count))
    total_size = Library.total_size_for_series(socket.assigns.access, series.id)
    sort = "issue_asc"
    books = sort_books(series.books, sort)
    cover_book = List.first(books)
    book_ids = Enum.map(series.books, & &1.id)
    progress_map = Library.progress_map(socket.assigns.current_user.id, book_ids)
    continue_book = find_continue_book(books, progress_map)
    summary_info = derive_summary(series, books)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Stashix.PubSub, "scan:#{library.id}")
      Metadata.subscribe(library.id)
    end

    {:ok,
     socket
     |> track_dialogs(~w(edit identify))
     |> assign(
       page_title: series.name,
       series: series,
       library: library,
       books: books,
       sort: sort,
       progress_map: progress_map,
       total_pages: total_pages,
       total_size: total_size,
       cover_book: cover_book,
       continue_book: continue_book,
       summary_info: summary_info,
       scanning: false,
       show_admin_menu: false,
       show_edit_dialog: false,
       show_identify_dialog: false,
       edit_form: nil,
       series_details: Library.series_details(socket.assigns.access, series.id),
       all_publishers: Library.list_all_publishers()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      if params["edit"] == "true" && socket.assigns.current_user.role == :admin do
        series = socket.assigns.series
        form = series |> Series.changeset(%{}) |> to_form()

        assign(socket,
          show_edit_dialog: true,
          edit_form: form
        )
      else
        assign(socket, show_edit_dialog: false, edit_form: nil)
      end

    socket =
      assign(socket,
        show_identify_dialog: params["identify"] == "true" && socket.assigns.current_user.role == :admin
      )

    {:noreply, socket}
  end

  # Age rating lives on books; the series-level setting overwrites every issue.
  defp maybe_cascade_age_rating(_series, rating, _only_unknown) when rating in [nil, ""], do: :ok

  defp maybe_cascade_age_rating(series, rating, only_unknown) do
    if rating != to_string(common_age_rating(series.books)) do
      with {:ok, ids} <-
             Library.set_series_age_rating(series.id, rating, only_unknown: only_unknown),
           true <- Stashix.Settings.metadata()["write_to_files"] do
        Enum.each(ids, &Metadata.enqueue_write/1)
      end
    end

    :ok
  end

  # The shared age rating of all issues, or nil when mixed/empty.
  defp common_age_rating(books) do
    case books |> Enum.map(& &1.age_rating) |> Enum.uniq() do
      [rating] -> rating
      _ -> nil
    end
  end

  defp year_range(%{start_year: nil}), do: nil
  defp year_range(%{start_year: s, end_year: nil, ongoing: true}), do: "#{s}–"
  defp year_range(%{start_year: s, end_year: nil}), do: "#{s}"
  defp year_range(%{start_year: s, end_year: e}), do: "#{s}–#{e}"

  defp relative_folder(series, library) do
    library.name <>
      "/" <>
      (String.replace_prefix(series.path || "", library.root_path, "")
       |> String.trim_leading("/"))
  end

  @impl true
  # Metadata editing and rescans are admin-only; the UI hides them for other
  # users, and this drops the events if sent anyway.
  def handle_event(event, _params, %{assigns: %{current_user: %{role: role}}} = socket)
      when event in @admin_events and role != :admin do
    {:noreply, socket}
  end

  def handle_event("sort", %{"value" => sort}, socket) do
    {:noreply, assign(socket, sort: sort, books: sort_books(socket.assigns.series.books, sort))}
  end

  def handle_event("toggle_admin_menu", _, socket) do
    {:noreply, assign(socket, show_admin_menu: !socket.assigns.show_admin_menu)}
  end

  def handle_event("open_edit_dialog", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/series/#{socket.assigns.series.id}?edit=true")}
  end

  def handle_event("close_edit_dialog", _params, socket) do
    {:noreply, close_dialog(socket, ~p"/series/#{socket.assigns.series.id}")}
  end

  def handle_event("save_metadata", %{"series" => params} = all_params, socket) do
    series = socket.assigns.series

    case Library.update_series(series, params) do
      {:ok, updated_series} ->
        maybe_cascade_age_rating(
          series,
          all_params["age_rating"],
          all_params["age_rating_only_unknown"] == "true"
        )

        series = Library.get_series_with_books(socket.assigns.access, updated_series.id)
        books = sort_books(series.books, socket.assigns.sort)

        {:noreply,
         socket
         |> assign(
           series: series,
           books: books,
           page_title: series.name,
           summary_info: derive_summary(series, books)
         )
         |> close_dialog(~p"/series/#{series.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, edit_form: to_form(changeset))}
    end
  end

  def handle_event("fetch_metadata", _params, socket) do
    case Metadata.enqueue_series(socket.assigns.series.id) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Looking up metadata for the series and its issues…")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not queue metadata lookup")}
    end
  end

  def handle_event("open_identify_dialog", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/series/#{socket.assigns.series.id}?identify=true")}
  end

  def handle_event("close_identify_dialog", _params, socket) do
    {:noreply, close_dialog(socket, ~p"/series/#{socket.assigns.series.id}")}
  end

  def handle_event("toggle_metadata_lock", _params, socket) do
    series = socket.assigns.series
    {:ok, _} = Metadata.set_locked(series, !series.metadata_locked)
    {:noreply, reload_series(socket)}
  end

  def handle_event("rescan_series", _, socket) do
    Scanner.scan_series(socket.assigns.series.id)
    {:noreply, assign(socket, scanning: true, show_admin_menu: false)}
  end

  def handle_event("force_rescan_series", _, socket) do
    Scanner.scan_series(socket.assigns.series.id, true)
    {:noreply, assign(socket, scanning: true, show_admin_menu: false)}
  end

  @impl true
  def handle_info({:scan_progress, %{done: true}}, socket) do
    series = Library.get_series_with_books(socket.assigns.access, socket.assigns.series.id)
    books = sort_books(series.books, socket.assigns.sort)
    book_ids = Enum.map(series.books, & &1.id)
    progress_map = Library.progress_map(socket.assigns.current_user.id, book_ids)
    total_pages = Enum.sum(Enum.map(series.books, & &1.page_count))
    total_size = Library.total_size_for_series(socket.assigns.access, series.id)

    {:noreply,
     assign(socket,
       scanning: false,
       series: series,
       books: books,
       progress_map: progress_map,
       total_pages: total_pages,
       total_size: total_size,
       cover_book: List.first(books),
       continue_book: find_continue_book(books, progress_map),
       summary_info: derive_summary(series, books)
     )}
  end

  def handle_info({:cover_updated, book_id}, socket) do
    if Enum.any?(socket.assigns.books, &(&1.id == book_id)),
      do: {:noreply, replace_book_cover(socket, book_id)},
      else: {:noreply, socket}
  end

  def handle_info({:scan_progress, _}, socket), do: {:noreply, socket}
  def handle_info({:book_added, _}, socket), do: {:noreply, socket}

  def handle_info({:metadata_updated, :series, id}, %{assigns: %{series: %{id: id}}} = socket),
    do: {:noreply, reload_series(socket)}

  def handle_info({:metadata_updated, :book, book_id}, socket) do
    if Enum.any?(socket.assigns.books, &(&1.id == book_id)),
      do: {:noreply, reload_series(socket)},
      else: {:noreply, socket}
  end

  def handle_info({:metadata_updated, _, _}, socket), do: {:noreply, socket}

  def handle_info({:identify_applied, :series, _id}, socket) do
    {:noreply,
     socket
     |> reload_series()
     |> put_flash(:info, "Series metadata applied")
     |> close_dialog(~p"/series/#{socket.assigns.series.id}")}
  end

  defp replace_book_cover(socket, book_id) do
    updated = Library.get_book_with_series(socket.assigns.access, book_id)

    books =
      Enum.map(socket.assigns.books, fn b ->
        if b.id == book_id, do: updated, else: b
      end)

    cover_book =
      if socket.assigns.cover_book && socket.assigns.cover_book.id == book_id,
        do: updated,
        else: socket.assigns.cover_book

    assign(socket, books: books, cover_book: cover_book)
  end

  defp reload_series(socket) do
    series = Library.get_series_with_books(socket.assigns.access, socket.assigns.series.id)
    books = sort_books(series.books, socket.assigns.sort)

    assign(socket,
      series: series,
      books: books,
      page_title: series.name,
      summary_info: derive_summary(series, books),
      series_details: Library.series_details(socket.assigns.access, series.id)
    )
  end

  defp find_continue_book(books, progress_map) do
    issue_sorted =
      Enum.sort_by(books, fn b ->
        if b.issue_number, do: Decimal.to_float(b.issue_number), else: 999_999.0
      end)

    in_progress =
      Enum.find(issue_sorted, fn b ->
        prog = progress_map[b.id]
        prog && prog > 0 && b.page_count && prog < b.page_count - 1
      end)

    in_progress ||
      Enum.find(issue_sorted, fn b ->
        prog = progress_map[b.id]
        is_nil(prog) || prog == 0
      end)
  end

  defp derive_summary(%{summary: s}, _books) when is_binary(s) and s != "",
    do: %{text: s, source: nil}

  defp derive_summary(_series, books) do
    issue_sorted =
      Enum.sort_by(books, fn b ->
        if b.issue_number, do: Decimal.to_float(b.issue_number), else: 999_999.0
      end)

    case Enum.find(issue_sorted, fn b -> b.summary && b.summary != "" end) do
      nil ->
        nil

      book ->
        %{
          text: book.summary,
          source: book.issue_number && "##{Decimal.to_integer(book.issue_number)}"
        }
    end
  end

  # Fraction read (0.0–1.0), or nil when the book has never been opened.
  defp book_progress(book, progress_map) do
    prog = progress_map[book.id]

    if prog && book.page_count && book.page_count > 1,
      do: min(prog / (book.page_count - 1), 1.0),
      else: nil
  end

  defp run_segment_title(book, progress_map) do
    state =
      case book_progress(book, progress_map) do
        p when p in [nil, 0.0] -> "unread"
        p when p >= 1.0 -> "read"
        p -> "#{round(p * 100)}% read"
      end

    [issue_label(book), book.title, state] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")
  end

  defp issue_label(%{issue_number: nil}), do: nil
  defp issue_label(%{issue_number: n}), do: "##{Decimal.to_integer(n)}"

  defp sort_books(books, "title_asc"), do: Enum.sort_by(books, & &1.title)
  defp sort_books(books, "title_desc"), do: Enum.sort_by(books, & &1.title, :desc)
  defp sort_books(books, "year_asc"), do: Enum.sort_by(books, &(&1.year || 0))
  defp sort_books(books, "year_desc"), do: Enum.sort_by(books, &(&1.year || 0), :desc)
  defp sort_books(books, "added_asc"), do: Enum.sort_by(books, & &1.inserted_at, NaiveDateTime)

  defp sort_books(books, "added_desc"),
    do: Enum.sort_by(books, & &1.inserted_at, {:desc, NaiveDateTime})

  defp sort_books(books, "issue_desc") do
    Enum.sort_by(
      books,
      fn b ->
        if b.issue_number, do: Decimal.to_float(b.issue_number), else: -1.0
      end,
      :desc
    )
  end

  defp sort_books(books, _) do
    Enum.sort_by(books, fn b ->
      if b.issue_number, do: Decimal.to_float(b.issue_number), else: 999_999.0
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <% issue_sorted = sort_books(@series.books, "issue_asc") %>
    <% first_book = List.first(issue_sorted) %>
    <% issue_count = length(issue_sorted) %>
    <% read_count = Enum.count(issue_sorted, &((book_progress(&1, @progress_map) || 0.0) >= 1.0)) %>
    <% has_cover = @cover_book && @cover_book.cover %>
    <.detail_page cover_src={has_cover && ~p"/api/books/#{@cover_book.id}/cover?s=s"}>
      <.detail_crumbs crumbs={[
        {"Home", "/"},
        {@library.name, ~p"/library/#{@library.id}"},
        {@series.name, nil}
      ]}>
        <:actions :if={@current_user.role == :admin}>
          <.dropdown_menu id="series-admin-menu">
            <.dropdown_menu_trigger class="flex items-center gap-1.5 px-3 h-8 text-xs font-medium rounded-full bg-white/5 hover:bg-white/15 text-gray-300 hover:text-white backdrop-blur-sm transition-colors">
              <.icon name="lucide-settings" class="w-3.5 h-3.5" /> Admin
              <.icon name="lucide-chevron-down" class="w-3 h-3" />
            </.dropdown_menu_trigger>
            <.dropdown_menu_content align="end" class="bg-gray-800 border-gray-700 min-w-44">
              <.dropdown_menu_item
                class="hover:bg-gray-700 focus:bg-gray-700 text-gray-300"
                on-select={JS.push("open_edit_dialog")}
              >
                <.icon name="lucide-pencil" class="w-4 h-4 mr-2" /> Edit Metadata
              </.dropdown_menu_item>
              <.dropdown_menu_item
                class="hover:bg-gray-700 focus:bg-gray-700 text-gray-300"
                on-select={JS.push("fetch_metadata")}
              >
                <.icon name="lucide-cloud-download" class="w-4 h-4 mr-2" /> Fetch Metadata
              </.dropdown_menu_item>
              <.dropdown_menu_item
                class="hover:bg-gray-700 focus:bg-gray-700 text-gray-300"
                on-select={JS.push("open_identify_dialog")}
              >
                <.icon name="lucide-scan-search" class="w-4 h-4 mr-2" /> Identify Series…
              </.dropdown_menu_item>
              <.dropdown_menu_item
                class="hover:bg-gray-700 focus:bg-gray-700 text-gray-300"
                on-select={JS.push("toggle_metadata_lock")}
              >
                <%= if @series.metadata_locked do %>
                  <.icon name="lucide-lock-open" class="w-4 h-4 mr-2" /> Unlock Metadata
                <% else %>
                  <.icon name="lucide-lock" class="w-4 h-4 mr-2" /> Lock Metadata
                <% end %>
              </.dropdown_menu_item>
              <.dropdown_menu_item
                class="hover:bg-gray-700 focus:bg-gray-700 text-gray-300"
                on-select={JS.push("rescan_series")}
              >
                <%= if @scanning do %>
                  <.icon
                    name="lucide-loader-circle"
                    class="w-4 h-4 mr-2 animate-spin text-violet-400"
                  /> Scanning…
                <% else %>
                  <.icon name="lucide-refresh-cw" class="w-4 h-4 mr-2" /> Rescan Series
                <% end %>
              </.dropdown_menu_item>
              <.dropdown_menu_item
                class="hover:bg-gray-700 focus:bg-gray-700 text-amber-400"
                on-select={JS.push("force_rescan_series")}
              >
                <%= if @scanning do %>
                  <.icon name="lucide-loader-circle" class="w-4 h-4 mr-2 animate-spin" /> Scanning…
                <% else %>
                  <.icon name="lucide-zap" class="w-4 h-4 mr-2" /> Force Rescan
                <% end %>
              </.dropdown_menu_item>
            </.dropdown_menu_content>
          </.dropdown_menu>
        </:actions>
      </.detail_crumbs>

      <%!-- Hero: fanned cover stack, giant issue count behind the title --%>
      <header class="relative flex flex-col items-center sm:flex-row sm:items-end gap-8 sm:gap-14 pt-2">
        <span
          :if={issue_count > 1}
          class="ghost-numeral hidden sm:block absolute -top-4 right-0 text-[11rem] md:text-[15rem] pointer-events-none"
          aria-hidden="true"
        >
          {issue_count}
        </span>

        <div class="rise" style="--i:0">
          <.hero_cover
            id={"series-cover-#{@series.id}"}
            src={has_cover && ~p"/api/books/#{@cover_book.id}/cover?s=l"}
            full_src={has_cover && ~p"/api/books/#{@cover_book.id}/cover?s=xl"}
            alt={@series.name}
            blurhash={has_cover && @cover_book.cover.blurhash}
            stack={
              issue_sorted
              |> Enum.filter(&(&1.cover && (!@cover_book || &1.id != @cover_book.id)))
              |> Enum.take(2)
              |> Enum.map(&~p"/api/books/#{&1.id}/cover?s=m")
            }
          />
        </div>

        <div class="relative min-w-0 flex-1 text-center sm:text-left sm:pb-2">
          <p
            :if={@series.publishers != []}
            class="rise text-[11px] font-bold tracking-[0.2em] uppercase text-violet-300 mb-3"
            style="--i:1"
          >
            <%= for {pub, idx} <- Enum.with_index(@series.publishers) do %>
              <span :if={idx > 0} class="text-white/25"> / </span>
              <.link navigate={~p"/publisher/#{pub.id}"} class="hover:text-white transition-colors">{pub.name}</.link>
            <% end %>
          </p>

          <h1
            class="rise font-display font-black uppercase text-5xl md:text-7xl leading-[0.88] text-white text-balance break-words"
            style="--i:2"
          >
            {@series.name}
          </h1>

          <div
            class="rise flex items-center justify-center sm:justify-start flex-wrap gap-x-3 gap-y-1 mt-4 text-sm text-gray-300"
            style="--i:3"
          >
            <span :if={yr = year_range(@series)} class="tabular-nums">{yr}</span>
            <%= if @series.ongoing do %>
              <span class="inline-flex items-center gap-1.5 text-emerald-300">
                <span class="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse"></span> Ongoing
              </span>
            <% else %>
              <span class="inline-flex items-center gap-1.5 text-gray-400">
                <span class="w-1.5 h-1.5 rounded-full bg-gray-500"></span> Completed
              </span>
            <% end %>
            <span class="tabular-nums">
              {issue_count} {if issue_count == 1, do: "issue", else: "issues"}
            </span>
          </div>

          <%!-- Read buttons --%>
          <%= if @continue_book do %>
            <% has_progress = (@progress_map[@continue_book.id] || 0) > 0 %>
            <div class="rise flex items-center justify-center sm:justify-start gap-5 flex-wrap mt-7" style="--i:4">
              <.link
                navigate={~p"/read/#{@continue_book.id}"}
                class="ink-btn inline-flex items-center gap-2.5 px-6 py-2.5 bg-violet-600 hover:bg-violet-500 text-white font-display font-extrabold uppercase text-xl tracking-wide rounded-md"
              >
                <.icon name="lucide-play" class="w-4 h-4" />
                {if has_progress, do: "Continue", else: "Start Reading"}
                <span :if={lbl = issue_label(@continue_book)} class="text-ink">{lbl}</span>
              </.link>
              <.link
                :if={has_progress && first_book && first_book.id != @continue_book.id}
                navigate={~p"/read/#{first_book.id}"}
                class="inline-flex items-center gap-2 text-sm font-medium text-gray-300 hover:text-white underline decoration-white/25 hover:decoration-white underline-offset-4 transition-colors"
              >
                <.icon name="lucide-rotate-ccw" class="w-4 h-4" /> Read from #1
              </.link>
            </div>
          <% end %>
        </div>
      </header>

      <%!-- The run: one segment per issue, filled by reading progress --%>
      <section :if={issue_count > 1} class="rise" style="--i:5">
        <div class="flex items-baseline justify-between mb-2">
          <h2 class="text-[10px] font-semibold tracking-[0.16em] uppercase text-gray-500">The run</h2>
          <p class="text-xs text-gray-400 tabular-nums">
            <span class="text-white font-semibold">{read_count}</span> / {issue_count} read
          </p>
        </div>
        <div class={["flex items-end h-7", if(issue_count <= 150, do: "gap-[2px]", else: "gap-0")]}>
          <.link
            :for={b <- issue_sorted}
            navigate={~p"/book/#{b.id}"}
            title={run_segment_title(b, @progress_map)}
            class={[
              "flex-1 min-w-0 rounded-[2px] overflow-hidden bg-white/10 hover:bg-white/30 hover:h-7 transition-[height,background-color] duration-150",
              if(@continue_book && b.id == @continue_book.id,
                do: "h-7 outline outline-1 outline-ink",
                else: "h-4"
              )
            ]}
          >
            <span
              class="block h-full bg-violet-500"
              style={"width: #{round((book_progress(b, @progress_map) || 0.0) * 100)}%"}
            ></span>
          </.link>
        </div>
      </section>

      <%!-- Summary --%>
      <section :if={@summary_info} class="max-w-3xl">
        <p class="text-[15px] text-gray-300 leading-7 whitespace-pre-line">{@summary_info.text}</p>
        <p :if={@summary_info.source} class="mt-2 text-xs text-gray-500 italic">
          From issue {@summary_info.source}
        </p>
      </section>

      <.indicia>
        <:item label="Pages" show={@total_pages > 0}>
          {@total_pages
          |> Integer.to_string()
          |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")}
        </:item>
        <:item label="Size" show={Formatters.format_file_size(@total_size) != nil}>
          {Formatters.format_file_size(@total_size)}
        </:item>
        <:item label="Volume" show={@series.volume != nil}>Vol. {@series.volume}</:item>
        <:item label="Language" show={@series.language != nil}>
          {Formatters.language_name(@series.language)}
        </:item>
        <:item label="Metadata" show={@series.metadata_locked}>
          <span class="inline-flex items-center gap-1 text-amber-300/90">
            <.icon name="lucide-lock" class="w-3 h-3" /> Locked
          </span>
        </:item>
      </.indicia>

      <%!-- Series details expander --%>
      <% sd = @series_details %>
      <% creator_groups = Roles.group_counts(sd.creators) %>
      <% headline_groups = Roles.headline(creator_groups) %>
      <% has_extras =
        sd.characters != [] || sd.teams != [] || sd.arcs != [] || sd.genres != [] ||
          creator_groups != [] %>
      <%= if headline_groups != [] || has_extras do %>
        <div class="space-y-3">
          <.credits_line groups={headline_groups} />
          <%= if has_extras do %>
            <.expander id="series-details">
              <.detail_section label="Creators" show={creator_groups != []}>
                <div class="space-y-2">
                  <div :for={{label, entries} <- creator_groups} class="flex flex-wrap gap-x-4 gap-y-0.5 text-sm">
                    <span class="w-20 shrink-0 text-[9px] font-bold tracking-[0.14em] uppercase text-gray-600 pt-0.5">{label}</span>
                    <span class="text-gray-300">
                      <span :for={{entry, i} <- Enum.with_index(entries)}>
                        <.link
                          navigate={"/search?creator=#{elem(entry, 2)}"}
                          class="hover:text-white hover:underline transition-colors"
                        >{elem(entry, 0)}</.link><span :if={i < length(entries) - 1}>, </span>
                      </span>
                    </span>
                  </div>
                </div>
              </.detail_section>

              <.detail_section label="Genres" show={sd.genres != []}>
                <.chips items={Enum.map(sd.genres, fn {name, count} -> {name, count} end)} />
              </.detail_section>

              <.detail_section label="Story Arcs" show={sd.arcs != []}>
                <.chips items={Enum.map(sd.arcs, fn {name, count} -> {name, count} end)} />
              </.detail_section>

              <.detail_section label="Characters" show={sd.characters != []}>
                <.chips items={Enum.map(sd.characters, fn {name, count} -> {name, count} end)} />
              </.detail_section>

              <.detail_section label="Teams" show={sd.teams != []}>
                <.chips items={Enum.map(sd.teams, fn {name, count} -> {name, count} end)} />
              </.detail_section>
            </.expander>
          <% end %>
        </div>
      <% end %>

      <%!-- Issues --%>
      <section>
        <div class="flex items-end justify-between mb-4">
          <h2 class="font-display font-black uppercase text-3xl leading-none text-white">
            Issues <span class="text-gray-600 tabular-nums">{issue_count}</span>
          </h2>
          <form phx-change="sort">
            <select
              name="value"
              aria-label="Sort issues"
              class="px-3 py-1.5 text-xs font-medium rounded-full border bg-white/5 border-white/10 text-gray-300 hover:text-white hover:border-white/25 focus:outline-none focus:border-violet-500 cursor-pointer transition-colors"
            >
              <%= for {label, value} <- [
                {"Issue # ↑", "issue_asc"},
                {"Issue # ↓", "issue_desc"},
                {"A → Z", "title_asc"},
                {"Z → A", "title_desc"},
                {"Year ↑", "year_asc"},
                {"Year ↓", "year_desc"},
                {"Date Added ↓", "added_desc"},
                {"Date Added ↑", "added_asc"}
              ] do %>
                <option value={value} selected={@sort == value} class="bg-gray-900">{label}</option>
              <% end %>
            </select>
          </form>
        </div>
        <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 gap-4">
          <%= for book <- @books do %>
            <.media_card
              navigate={~p"/book/#{book.id}"}
              title={book.title}
              cover_url={~p"/api/books/#{book.id}/cover"}
              size="m"
              subtitle={book.year && to_string(book.year)}
              badge={
                cond do
                  book.volume && book.issue_number -> "Vol. #{book.volume}  ##{book.issue_number}"
                  book.issue_number -> "##{book.issue_number}"
                  true -> nil
                end
              }
              progress={book_progress(book, @progress_map)}
              type={:book}
              blurhash={book.cover && book.cover.blurhash}
            />
          <% end %>
        </div>
      </section>

      <%!-- Folder path --%>
      <div
        :if={@current_user.role == :admin && @series.path}
        class="flex items-start gap-1.5 text-[11px] font-mono text-gray-600 break-all leading-snug"
      >
        <.icon name="lucide-folder" class="w-3 h-3 flex-shrink-0 mt-0.5 text-gray-700" />
        {relative_folder(@series, @library)}
      </div>
    </.detail_page>

    <%!-- Identify Dialog --%>
    <%= if @current_user.role == :admin && @show_identify_dialog do %>
      <.live_component module={StashixWeb.IdentifyComponent} id="identify-series" target={@series} />
    <% end %>

    <%!-- Edit Metadata Dialog --%>
    <%= if @current_user.role == :admin && @show_edit_dialog do %>
      <.dialog id="edit-series-dialog" open={true} on-close={JS.push("close_edit_dialog")}>
        <.dialog_content class="sm:max-w-xl !bg-gray-900 !border-gray-700 text-white">
          <.dialog_header>
            <.dialog_title class="text-white">Edit Series Metadata</.dialog_title>
            <.dialog_description class="text-gray-400">
              Override metadata for this series. Changes persist until the next rescan.
            </.dialog_description>
            <%= if @series.path do %>
              <p class="flex items-center gap-1.5 text-xs font-mono text-gray-500 mt-1 break-all">
                <.icon name="lucide-folder" class="w-3 h-3 flex-shrink-0" />
                {relative_folder(@series, @library)}
              </p>
            <% end %>
          </.dialog_header>

          <.form for={@edit_form} phx-submit="save_metadata" class="space-y-3 mt-2">
            <div class="grid grid-cols-2 gap-x-4 gap-y-3">
              <div class="col-span-2">
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Name</label>
                <input
                  type="text"
                  name="series[name]"
                  value={@edit_form[:name].value}
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                />
              </div>

              <div class="col-span-2">
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Summary</label>
                <textarea
                  name="series[summary]"
                  rows="4"
                  placeholder="Leave blank to inherit from first issue with a summary…"
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500 resize-none"
                >{@edit_form[:summary].value}</textarea>
              </div>

              <div>
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Volume</label>
                <input
                  type="number"
                  name="series[volume]"
                  value={@edit_form[:volume].value}
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Language</label>
                <input
                  type="text"
                  name="series[language]"
                  value={@edit_form[:language].value}
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Start Year</label>
                <input
                  type="number"
                  name="series[start_year]"
                  value={@edit_form[:start_year].value}
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-gray-400 mb-1.5">End Year</label>
                <input
                  type="number"
                  name="series[end_year]"
                  value={@edit_form[:end_year].value}
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                />
              </div>

              <div class="col-span-2">
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Age Rating</label>
                <% current_rating = common_age_rating(@series.books) %>
                <select
                  name="age_rating"
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                >
                  <option value="" selected={is_nil(current_rating)}>
                    {if @series.books == [], do: "No issues", else: "Mixed — keep per-issue ratings"}
                  </option>
                  <%= for {label, val} <- [{"Unknown", "unknown"}, {"Everyone", "everyone"}, {"Teen", "teen"}, {"Teen+", "teen_plus"}, {"Mature", "mature"}, {"Adult", "adult"}, {"Explicit", "explicit"}] do %>
                    <option value={val} selected={to_string(current_rating) == val}>{label}</option>
                  <% end %>
                </select>
                <% mixed = is_nil(current_rating) && @series.books != [] %>
                <% unknown_count = Enum.count(@series.books, &(&1.age_rating in [:unknown, nil])) %>
                <div :if={mixed} class="flex items-center gap-2 mt-2">
                  <input type="hidden" name="age_rating_only_unknown" value="false" />
                  <input
                    type="checkbox"
                    id="age_rating_only_unknown"
                    name="age_rating_only_unknown"
                    value="true"
                    checked
                    class="rounded border-gray-600 bg-gray-800 text-violet-500 focus:ring-violet-500"
                  />
                  <label for="age_rating_only_unknown" class="text-sm text-gray-300 cursor-pointer">
                    Only update issues rated Unknown ({unknown_count})
                  </label>
                </div>
                <p class="flex items-start gap-1.5 text-xs text-amber-400/80 mt-1.5">
                  <.icon name="lucide-triangle-alert" class="w-3.5 h-3.5 mt-px flex-shrink-0" />
                  <%= if mixed do %>
                    Issues have different ratings. Unchecking the box above overwrites the age rating of all {length(
                      @series.books
                    )} issues.
                  <% else %>
                    Changing this overwrites the age rating of all {length(@series.books)} issues in this series.
                  <% end %>
                </p>
              </div>

              <div class="col-span-2 flex items-center gap-3">
                <input
                  type="hidden"
                  name="series[ongoing]"
                  value="false"
                />
                <input
                  type="checkbox"
                  id="series_ongoing"
                  name="series[ongoing]"
                  value="true"
                  checked={@edit_form[:ongoing].value}
                  class="rounded border-gray-600 bg-gray-800 text-violet-500 focus:ring-violet-500"
                />
                <label for="series_ongoing" class="text-sm text-gray-300 cursor-pointer">Ongoing series</label>
              </div>

              <div class="col-span-2">
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Publisher</label>
                <div
                  id={"pub-picker-series-#{@series.id}"}
                  phx-hook="PublisherSearch"
                  class="relative"
                  data-publishers={Jason.encode!(Enum.map(@all_publishers, &%{id: &1.id, name: &1.name}))}
                  data-selected-ids={Jason.encode!(Enum.map(@series.publishers, & &1.id))}
                  data-input-name="series[publisher_ids][]"
                >
                  <div class="pub-badges flex flex-wrap gap-1.5 mb-2" hidden></div>
                  <input
                    type="text"
                    placeholder="Search publishers…"
                    autocomplete="off"
                    class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                  />
                </div>
              </div>
            </div>

            <.dialog_footer class="pt-2">
              <button
                type="button"
                phx-click="close_edit_dialog"
                class="inline-flex items-center justify-center rounded-md px-4 py-2 text-sm font-medium border border-red-700 text-red-400 bg-transparent hover:bg-red-900/30 hover:text-red-300 transition-colors"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="inline-flex items-center justify-center rounded-md px-4 py-2 text-sm font-medium bg-emerald-600 hover:bg-emerald-500 text-white transition-colors"
              >
                Save Changes
              </button>
            </.dialog_footer>
          </.form>
        </.dialog_content>
      </.dialog>
    <% end %>
    """
  end
end
