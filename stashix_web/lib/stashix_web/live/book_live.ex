defmodule StashixWeb.BookLive do
  use StashixWeb, :live_view

  alias Stashix.{Formatters, Library, Metadata, Repo, Scanner}
  alias Stashix.Library.Book
  alias Stashix.Metadata.Roles
  import StashixWeb.MetadataComponents
  import StashixWeb.DetailComponents
  import StashixWeb.DialogHistory

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @admin_events ~w(save_metadata fetch_metadata toggle_metadata_lock rescan_book)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    book = Library.get_book_with_series(socket.assigns.access, id)
    library = Library.get_readable_library!(socket.assigns.access, book.library_id)

    progress = Library.get_progress(socket.assigns.current_user.id, id)
    current_page = (progress && progress.current_page) || 0
    fully_read = book.page_count > 0 && current_page >= book.page_count - 1
    {prev_book, next_book} = Library.get_adjacent_books(socket.assigns.access, book)
    selected_file = Library.get_preferred_book_file(book)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Stashix.PubSub, "scan:#{library.id}")
      Metadata.subscribe(library.id)
    end

    {:ok,
     socket
     |> track_dialogs(~w(edit identify))
     |> assign(
       page_title: book.title,
       book: book,
       library: library,
       progress: current_page,
       fully_read: fully_read,
       prev_book: prev_book,
       next_book: next_book,
       selected_file: selected_file,
       read_menu_open: false,
       scanning: false,
       show_admin_menu: false,
       show_edit_dialog: false,
       show_identify_dialog: false,
       edit_form: nil,
       external_ids: load_external_ids(book),
       book_details: Library.get_book_details(socket.assigns.access, book.id),
       all_publishers: Library.list_all_publishers()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      if params["edit"] == "true" && socket.assigns.current_user.role == :admin do
        book = socket.assigns.book
        form = book |> Book.changeset(%{}) |> to_form()
        assign(socket, show_edit_dialog: true, edit_form: form)
      else
        assign(socket, show_edit_dialog: false, edit_form: nil)
      end

    socket =
      assign(socket,
        show_identify_dialog: params["identify"] == "true" && socket.assigns.current_user.role == :admin
      )

    {:noreply, socket}
  end

  @impl true
  # Metadata editing and rescans are admin-only; the UI hides them for other
  # users, and this drops the events if sent anyway.
  def handle_event(event, _params, %{assigns: %{current_user: %{role: role}}} = socket)
      when event in @admin_events and role != :admin do
    {:noreply, socket}
  end

  def handle_event("toggle_read_menu", _params, socket) do
    {:noreply, assign(socket, read_menu_open: !socket.assigns.read_menu_open)}
  end

  def handle_event("close_read_menu", _params, socket) do
    {:noreply, assign(socket, read_menu_open: false)}
  end

  def handle_event("mark_unread", _params, socket) do
    Library.update_progress(socket.assigns.access, socket.assigns.current_user.id, socket.assigns.book.id, 0)
    {:noreply, assign(socket, progress: 0, fully_read: false, read_menu_open: false)}
  end

  def handle_event("mark_read", _params, socket) do
    book = socket.assigns.book
    Library.update_progress(socket.assigns.access, socket.assigns.current_user.id, book.id, book.page_count)
    {:noreply, assign(socket, progress: book.page_count, fully_read: true, read_menu_open: false)}
  end

  def handle_event("toggle_admin_menu", _params, socket) do
    {:noreply, assign(socket, show_admin_menu: !socket.assigns.show_admin_menu)}
  end

  def handle_event("open_edit_dialog", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/book/#{socket.assigns.book.id}?edit=true")}
  end

  def handle_event("close_edit_dialog", _params, socket) do
    {:noreply, close_dialog(socket, ~p"/book/#{socket.assigns.book.id}")}
  end

  def handle_event("save_metadata", %{"book" => params}, socket) do
    book = socket.assigns.book

    case Library.update_book(book, params) do
      {:ok, updated_book} ->
        if Stashix.Settings.metadata()["write_to_files"], do: Metadata.enqueue_write(updated_book.id)
        book = Library.get_book_with_series(socket.assigns.access, updated_book.id)

        {:noreply,
         socket
         |> assign(book: book, page_title: book.title)
         |> close_dialog(~p"/book/#{book.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, edit_form: to_form(changeset))}
    end
  end

  def handle_event("select_format", %{"format" => fmt}, socket) do
    book = socket.assigns.book
    fmt_atom = String.to_existing_atom(fmt)
    file = Enum.find(book.files, &(&1.format == fmt_atom))
    {:noreply, assign(socket, selected_file: file)}
  end

  def handle_event("fetch_metadata", _params, socket) do
    case Metadata.enqueue_book(socket.assigns.book.id) do
      {:ok, _} -> {:noreply, put_flash(socket, :info, "Looking up metadata in the background…")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not queue metadata lookup")}
    end
  end

  def handle_event("open_identify_dialog", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/book/#{socket.assigns.book.id}?identify=true")}
  end

  def handle_event("close_identify_dialog", _params, socket) do
    {:noreply, close_dialog(socket, ~p"/book/#{socket.assigns.book.id}")}
  end

  def handle_event("toggle_metadata_lock", _params, socket) do
    book = socket.assigns.book
    {:ok, _} = Metadata.set_locked(book, !book.metadata_locked)
    {:noreply, reload_book(socket)}
  end

  def handle_event("rescan_book", _params, socket) do
    Scanner.scan_book(socket.assigns.book.id)
    {:noreply, assign(socket, scanning: true, show_admin_menu: false)}
  end

  @impl true
  def handle_info({:scan_progress, %{done: true}}, socket) do
    book = Library.get_book_with_series(socket.assigns.access, socket.assigns.book.id)
    progress = Library.get_progress(socket.assigns.current_user.id, book.id)
    current_page = (progress && progress.current_page) || 0
    fully_read = book.page_count > 0 && current_page >= book.page_count - 1
    {prev_book, next_book} = Library.get_adjacent_books(socket.assigns.access, book)

    current_format = socket.assigns.selected_file && socket.assigns.selected_file.format
    selected_file = Library.get_preferred_book_file(book, current_format)

    {:noreply,
     assign(socket,
       scanning: false,
       book: book,
       progress: current_page,
       fully_read: fully_read,
       page_title: book.title,
       prev_book: prev_book,
       next_book: next_book,
       selected_file: selected_file
     )}
  end

  def handle_info({:cover_updated, book_id}, socket) do
    if socket.assigns.book.id == book_id do
      book = Library.get_book_with_series(socket.assigns.access, book_id)
      {:noreply, assign(socket, book: book)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:scan_progress, _}, socket), do: {:noreply, socket}
  def handle_info({:book_added, _}, socket), do: {:noreply, socket}

  def handle_info({:metadata_updated, :book, id}, %{assigns: %{book: %{id: id}}} = socket) do
    {:noreply, reload_book(socket)}
  end

  def handle_info({:metadata_updated, _, _}, socket), do: {:noreply, socket}

  def handle_info({:identify_applied, :book, _id}, socket) do
    {:noreply,
     socket
     |> reload_book()
     |> put_flash(:info, "Metadata applied")
     |> close_dialog(~p"/book/#{socket.assigns.book.id}")}
  end

  defp reload_book(socket) do
    book = Library.get_book_with_series(socket.assigns.access, socket.assigns.book.id)
    current_format = socket.assigns.selected_file && socket.assigns.selected_file.format

    assign(socket,
      book: book,
      page_title: book.title,
      external_ids: load_external_ids(book),
      book_details: Library.get_book_details(socket.assigns.access, book.id),
      selected_file: Library.get_preferred_book_file(book, current_format)
    )
  end

  defp load_external_ids(book), do: Repo.preload(book, [:external_ids, :urls]) |> Map.take([:external_ids, :urls])

  # `{label, href}` pills: one per external ID, then any stored URL for a site not already linked.
  # A stored URL for the source's own site wins over the one built from the ID.
  defp external_links(%{external_ids: ids, urls: urls}) do
    sources =
      Enum.map(ids, fn e ->
        source = to_string(e.source)

        {host, fallback} =
          case source do
            "Comic Vine" -> {"comicvine.gamespot.com", "https://comicvine.gamespot.com/issue/4000-#{e.source_id}/"}
            "Grand Comics Database" -> {"comics.org", "https://www.comics.org/issue/#{e.source_id}/"}
            "Metron" -> {"metron.cloud", nil}
            _ -> {nil, nil}
          end

        {source, (host && Enum.find_value(urls, &(url_host(&1.url) == host && &1.url))) || fallback}
      end)

    linked = for {_source, href} <- sources, href, do: url_host(href)

    sources ++ for(u <- urls, url_host(u.url) not in linked, do: {url_host(u.url) || u.url, u.url})
  end

  defp url_host(url) do
    case URI.parse(url).host do
      nil -> nil
      host -> String.replace_prefix(host, "www.", "")
    end
  end

  # Scalar facts for the details grid; empty values are dropped by the grid.
  defp book_facts(d) do
    [
      {"Stories", Enum.map_join(d.stories, ", ", & &1.name)},
      {"Story Arcs",
       Enum.map_join(d.story_arcs, ", ", fn a ->
         if a.arc_number, do: "#{a.name} ##{a.arc_number}", else: a.name
       end)},
      {"Imprint", d.imprint && d.imprint.name},
      {"Type", d.type not in [nil, "", "issue"] && String.capitalize(d.type)},
      {"Collection", d.collection_title},
      {"Alt. number", d.alternative_number},
      {"Cover date", d.cover_date && Calendar.strftime(d.cover_date, "%B %Y")},
      {"In stores", d.store_date && Calendar.strftime(d.store_date, "%Y-%m-%d")},
      {"Price", Enum.map_join(d.prices, " / ", fn p -> "#{p.amount} #{p.country}" end)},
      {"Community rating", community_rating(d)},
      {"ISBN", d.isbn},
      {"UPC", d.upc}
    ]
    |> Enum.map(fn {label, value} -> {label, value || nil} end)
  end

  defp community_rating(%{community_rating: nil}), do: nil

  defp community_rating(%{community_rating: rating, community_rating_count: count}) do
    votes = if count && count > 0, do: " · #{count} #{if count == 1, do: "vote", else: "votes"}", else: ""
    "#{Float.round(rating, 1)}#{votes}"
  end

  defp book_display_title(book), do: book.title

  # A CV "volume" with exactly one issue is a standalone TPB/OGN — don't show
  # the series eyebrow (it would duplicate the title) or a meaningless "#1" prefix.
  defp standalone_volume?(%{series: %{issue_count: 1}}), do: true
  defp standalone_volume?(_), do: false

  defp relative_path(path, library) do
    library.name <>
      "/" <> (String.replace_prefix(path, library.root_path, "") |> String.trim_leading("/"))
  end

  attr :book, :map, required: true
  attr :dir, :atom, required: true, values: [:prev, :next]

  defp adjacent_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/book/#{@book.id}"}
      class={[
        "group flex items-center gap-4 min-w-0 p-2 rounded-md bg-white/[0.03] hover:bg-white/[0.08] ring-1 ring-white/10 hover:ring-white/25 transition-colors",
        @dir == :next && "flex-row-reverse text-right"
      ]}
    >
      <div class="relative w-12 md:w-16 aspect-[2/3] flex-shrink-0 rounded-sm overflow-hidden bg-gray-900">
        <.blurhash_image
          id={"nav-#{@dir}-#{@book.id}"}
          src={~p"/api/books/#{@book.id}/cover?s=s"}
          blurhash={@book.blurhash}
          onerror="this.style.display='none'"
        />
      </div>
      <div class="min-w-0 flex-1">
        <p class={[
          "flex items-center gap-1 text-[10px] font-semibold tracking-[0.16em] uppercase text-gray-500",
          @dir == :next && "justify-end"
        ]}>
          <.icon :if={@dir == :prev} name="lucide-arrow-left" class="w-3 h-3" />
          {if @dir == :prev, do: "Previous", else: "Next"}
          <.icon :if={@dir == :next} name="lucide-arrow-right" class="w-3 h-3" />
        </p>
        <p :if={@book.issue_number} class="font-display font-black text-2xl leading-none text-white mt-1 tabular-nums">
          #{Decimal.to_integer(@book.issue_number)}
        </p>
        <p class="text-xs text-gray-400 truncate group-hover:text-gray-200 transition-colors mt-1">
          {@book.title}
        </p>
        <p class="text-[10px] text-gray-600 mt-0.5 tabular-nums">
          {[@book.year, @book.page_count > 0 && "#{@book.page_count} pp"]
          |> Enum.filter(& &1)
          |> Enum.join(" · ")}
        </p>
      </div>
    </.link>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <% numbered = @book.issue_number && !standalone_volume?(@book) %>
    <% issue_no = numbered && Decimal.to_integer(@book.issue_number) %>
    <% in_progress = !@fully_read && @progress > 0 && @book.page_count > 0 %>
    <.detail_page cover_src={@book.cover && ~p"/api/books/#{@book.id}/cover?s=s"}>
      <.detail_crumbs crumbs={
        [{"Home", "/"}, {@library.name, ~p"/library/#{@library.id}"}] ++
          if(@book.series, do: [{@book.series.name, ~p"/series/#{@book.series.id}"}], else: []) ++
          [{if(numbered, do: "##{issue_no}", else: @book.title), nil}]
      }>
        <:actions :if={@current_user.role == :admin}>
          <.dropdown_menu id="book-admin-menu">
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
                <.icon name="lucide-scan-search" class="w-4 h-4 mr-2" /> Identify…
              </.dropdown_menu_item>
              <.dropdown_menu_item
                class="hover:bg-gray-700 focus:bg-gray-700 text-gray-300"
                on-select={JS.push("toggle_metadata_lock")}
              >
                <%= if @book.metadata_locked do %>
                  <.icon name="lucide-lock-open" class="w-4 h-4 mr-2" /> Unlock Metadata
                <% else %>
                  <.icon name="lucide-lock" class="w-4 h-4 mr-2" /> Lock Metadata
                <% end %>
              </.dropdown_menu_item>
              <.dropdown_menu_item
                class="hover:bg-gray-700 focus:bg-gray-700 text-amber-400 disabled:opacity-50"
                on-select={JS.push("rescan_book")}
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

      <%!-- Hero: tilted cover, giant issue number behind the title --%>
      <header class="relative flex flex-col items-center sm:flex-row sm:items-end gap-8 sm:gap-10 pt-2">
        <span
          :if={numbered}
          class="ghost-numeral hidden sm:block absolute -top-4 right-0 text-[11rem] md:text-[15rem] pointer-events-none"
          aria-hidden="true"
        >
          {issue_no}
        </span>

        <.hero_cover
          id={"book-cover-#{@book.id}"}
          src={@book.cover && ~p"/api/books/#{@book.id}/cover?s=l"}
          full_src={@book.cover && ~p"/api/books/#{@book.id}/cover?s=xl"}
          alt={@book.title}
          blurhash={@book.cover && @book.cover.blurhash}
        />

        <div class="relative min-w-0 flex-1 text-center sm:text-left sm:pb-2">
          <%!-- Issue sticker + series eyebrow --%>
          <div
            :if={numbered || (@book.series && !standalone_volume?(@book))}
            class="rise flex items-center justify-center sm:justify-start flex-wrap gap-x-3 gap-y-2 mb-3"
            style="--i:1"
          >
            <span
              :if={numbered}
              class="inline-block -rotate-3 px-2 pt-0.5 rounded-sm bg-ink text-gray-950 font-display font-black text-2xl leading-none tabular-nums"
            >
              #{issue_no}
            </span>
            <p
              :if={@book.series && !standalone_volume?(@book)}
              class="text-[11px] font-bold tracking-[0.2em] uppercase text-violet-300"
            >
              <.link navigate={~p"/series/#{@book.series.id}"} class="hover:text-white transition-colors">
                {@book.series.name}
              </.link>
              <span :if={@book.series.start_year} class="text-gray-500 tracking-normal font-normal ml-1">
                ({@book.series.start_year}{cond do
                  @book.series.end_year -> "–#{@book.series.end_year}"
                  @book.series.ongoing -> "–"
                  true -> ""
                end})
              </span>
            </p>
          </div>

          <h1
            class="rise font-display font-black uppercase text-5xl md:text-7xl leading-[0.88] text-white text-balance break-words"
            style="--i:2"
          >
            {book_display_title(@book)}
          </h1>

          <div
            class="rise flex items-center justify-center sm:justify-start flex-wrap gap-x-3 gap-y-1 mt-4 text-sm text-gray-300 tabular-nums"
            style="--i:3"
          >
            <span :if={@book.year}>{@book.year}</span>
            <span :if={@book.page_count > 0}>{@book.page_count} pages</span>
            <span :if={@fully_read} class="inline-flex items-center gap-1 text-emerald-300">
              <.icon name="lucide-check" class="w-3.5 h-3.5" /> Read
            </span>
            <span :if={in_progress} class="text-violet-300">
              Page {@progress} of {@book.page_count}
            </span>
          </div>

          <%!-- Progress bar --%>
          <div
            :if={in_progress}
            class="rise h-1.5 mt-3 mx-auto sm:mx-0 max-w-xs rounded-full bg-white/10 overflow-hidden"
            style="--i:3"
            role="progressbar"
            aria-valuemin="0"
            aria-valuemax={@book.page_count}
            aria-valuenow={@progress}
          >
            <div class="h-full bg-violet-500 rounded-full" style={"width: #{round(@progress / @book.page_count * 100)}%"}>
            </div>
          </div>

          <%!-- Format pills (only when multiple files exist) --%>
          <div
            :if={length(@book.files) > 1}
            class="rise flex items-center justify-center sm:justify-start gap-1.5 mt-5"
            style="--i:4"
          >
            <span class="text-[10px] font-semibold tracking-[0.16em] uppercase text-gray-500 mr-1">Format</span>
            <%= for f <- @book.files do %>
              <%= if @selected_file && f.id == @selected_file.id do %>
                <span class="px-2.5 py-1 text-xs font-semibold rounded-full bg-white text-gray-950">
                  {String.upcase(to_string(f.format))}
                </span>
              <% else %>
                <button
                  phx-click="select_format"
                  phx-value-format={to_string(f.format)}
                  class="px-2.5 py-1 text-xs font-semibold rounded-full border border-white/15 text-gray-300 hover:border-white/50 hover:text-white transition-colors"
                >
                  {String.upcase(to_string(f.format))}
                </button>
              <% end %>
            <% end %>
          </div>

          <%!-- Read button --%>
          <div
            :if={@book.page_count > 0 && @selected_file}
            class="ink-split rise relative z-10 inline-flex items-stretch rounded-md mt-7"
            style="--i:5"
          >
            <.link
              navigate={
                if @fully_read,
                  do: ~p"/read/#{@book.id}?#{[page: 0, format: @selected_file.format]}",
                  else: ~p"/read/#{@book.id}?#{[format: @selected_file.format]}"
              }
              class="inline-flex items-center gap-2.5 px-6 py-2.5 bg-violet-600 hover:bg-violet-500 text-white font-display font-extrabold uppercase text-xl tracking-wide rounded-l-md transition-colors"
            >
              <.icon name="lucide-play" class="w-4 h-4" />
              {cond do
                @fully_read -> "Read Again"
                @progress > 0 -> "Continue"
                true -> "Read"
              end}
            </.link>
            <.dropdown_menu id="read-options-menu" class="flex">
              <.dropdown_menu_trigger
                class="flex items-center px-2.5 bg-violet-700 hover:bg-violet-600 text-white rounded-r-md border-l border-violet-400/40 transition-colors"
                aria-label="More reading options"
              >
                <.icon name="lucide-chevron-down" class="w-4 h-4" />
              </.dropdown_menu_trigger>
              <.dropdown_menu_content align="end" class="bg-gray-800 border-gray-700 min-w-48">
                <.link
                  navigate={~p"/read/#{@book.id}?#{[page: 0, format: @selected_file.format]}"}
                  hidden={@progress == 0 || @fully_read}
                  class="relative flex items-center rounded-sm px-2 py-1.5 text-sm text-gray-300 hover:bg-gray-700 cursor-default select-none outline-none"
                >
                  <.icon name="lucide-rotate-ccw" class="w-4 h-4 mr-2" /> Read from Beginning
                </.link>
                <button
                  phx-click={
                    JS.push("mark_read")
                    |> JS.dispatch("salad_ui:command", to: "#read-options-menu", detail: %{command: "close"})
                  }
                  hidden={@fully_read}
                  class="relative flex w-full items-center rounded-sm px-2 py-1.5 text-sm text-gray-300 hover:bg-gray-700 cursor-default select-none outline-none"
                >
                  <.icon name="lucide-circle-check-big" class="w-4 h-4 mr-2" /> Mark as Read
                </button>
                <button
                  phx-click={
                    JS.push("mark_unread")
                    |> JS.dispatch("salad_ui:command", to: "#read-options-menu", detail: %{command: "close"})
                  }
                  hidden={!@fully_read && @progress == 0}
                  class="relative flex w-full items-center rounded-sm px-2 py-1.5 text-sm text-gray-300 hover:bg-gray-700 cursor-default select-none outline-none"
                >
                  <.icon name="lucide-circle-x" class="w-4 h-4 mr-2" /> Mark as Unread
                </button>
              </.dropdown_menu_content>
            </.dropdown_menu>
          </div>
        </div>
      </header>

      <%!-- Summary --%>
      <section :if={@book.summary && @book.summary != ""} class="max-w-3xl">
        <p class="text-[15px] text-gray-300 leading-7 whitespace-pre-line">{@book.summary}</p>
      </section>

      <.indicia>
        <:item label="Publisher" show={@book.publishers != []}>
          <%= for {pub, idx} <- Enum.with_index(@book.publishers) do %>
            <span :if={idx > 0} class="text-gray-600"> / </span>
            <.link navigate={~p"/publisher/#{pub.id}"} class="hover:text-violet-300 transition-colors">{pub.name}</.link>
          <% end %>
        </:item>
        <:item label="Format">
          {if @selected_file, do: String.upcase(to_string(@selected_file.format)), else: "—"}
        </:item>
        <:item label="Size" show={@selected_file != nil && @selected_file.file_size > 0}>
          {Formatters.format_file_size(@selected_file.file_size)}
        </:item>
        <:item label="Language" show={@book.language != nil}>
          {Formatters.language_name(@book.language)}
        </:item>
        <:item label="Age Rating">{Formatters.format_age_rating(@book.age_rating)}</:item>
      </.indicia>

      <.details_panel
        id="book-details"
        credits={Roles.group(@book_details.credits)}
        facts={book_facts(@book_details)}
        genres={Enum.map(@book_details.genres, & &1.name)}
        tags={Enum.map(@book_details.tags, & &1.name)}
        characters={Enum.map(@book_details.characters, & &1.name)}
        teams={Enum.map(@book_details.teams, & &1.name)}
        locations={Enum.map(@book_details.locations, & &1.name)}
        universes={
          Enum.map(@book_details.universes, fn u ->
            if u.designation in [nil, ""], do: u.name, else: "#{u.name} (#{u.designation})"
          end)
        }
        reprints={Enum.map(@book_details.reprints, & &1.name)}
        links={external_links(@external_ids)}
        notes={@book.notes}
      />

      <%!-- Prev / Next navigation --%>
      <nav :if={@prev_book || @next_book} class="grid grid-cols-2 gap-3" aria-label="Adjacent issues">
        <.adjacent_card :if={@prev_book} book={@prev_book} dir={:prev} />
        <div :if={!@prev_book}></div>
        <.adjacent_card :if={@next_book} book={@next_book} dir={:next} />
      </nav>

      <%!-- Metadata source + file path --%>
      <footer class="space-y-2">
        <%= if @book.metadata_locked || @book.metadata_matched_at do %>
          <div class="flex flex-wrap items-center gap-2 text-xs text-gray-500">
            <%= if @book.metadata_locked do %>
              <span class="inline-flex items-center gap-1 text-amber-400/80" title="Excluded from automatic matching">
                <.icon name="lucide-lock" class="w-3 h-3" /> Locked
              </span>
            <% end %>
            <%= if @book.metadata_matched_at do %>
              <span>
                Metadata from {(Stashix.Metadata.Sources.module(@book.metadata_source || "") &&
                                  Stashix.Metadata.Sources.module(@book.metadata_source).name()) ||
                  @book.metadata_source} · {Calendar.strftime(@book.metadata_matched_at, "%Y-%m-%d")}
              </span>
            <% end %>
          </div>
        <% end %>
        <div
          :if={@current_user.role == :admin && @selected_file}
          class="flex items-start gap-1.5 text-[11px] font-mono text-gray-600 break-all leading-snug"
        >
          <.icon name="lucide-file" class="w-3 h-3 flex-shrink-0 mt-0.5 text-gray-700" />
          {relative_path(@selected_file.path, @library)}
        </div>
      </footer>
    </.detail_page>

    <%!-- Identify Dialog --%>
    <%= if @current_user.role == :admin && @show_identify_dialog do %>
      <.live_component module={StashixWeb.IdentifyComponent} id="identify-book" target={@book} />
    <% end %>

    <%!-- Edit Metadata Dialog --%>
    <%= if @current_user.role == :admin && @show_edit_dialog do %>
      <.dialog id="edit-metadata-dialog" open={true} on-close={JS.push("close_edit_dialog")}>
        <.dialog_content class="sm:max-w-xl !bg-gray-900 !border-gray-700 text-white">
          <.dialog_header>
            <.dialog_title class="text-white">Edit Metadata</.dialog_title>
            <.dialog_description class="text-gray-400">
              Override metadata for this book. Changes persist until the next rescan.
            </.dialog_description>
            <%= if @selected_file do %>
              <p class="flex items-center gap-1.5 text-xs font-mono text-gray-500 mt-1 break-all">
                <.icon name="lucide-file" class="w-3 h-3 flex-shrink-0" />
                {relative_path(@selected_file.path, @library)}
              </p>
            <% end %>
          </.dialog_header>

          <.form for={@edit_form} phx-submit="save_metadata" class="space-y-3 mt-2">
            <div class="grid grid-cols-2 gap-x-4 gap-y-3">
              <div class="col-span-2">
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Title</label>
                <input
                  type="text"
                  name="book[title]"
                  value={@edit_form[:title].value}
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Issue #</label>
                <input
                  type="text"
                  name="book[issue_number]"
                  value={@edit_form[:issue_number].value}
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Volume</label>
                <input
                  type="number"
                  name="book[volume]"
                  value={@edit_form[:volume].value}
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Year</label>
                <input
                  type="number"
                  name="book[year]"
                  value={@edit_form[:year].value}
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Language</label>
                <input
                  type="text"
                  name="book[language]"
                  value={@edit_form[:language].value}
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                />
              </div>

              <div class="col-span-2">
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Age Rating</label>
                <select
                  name="book[age_rating]"
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                >
                  <%= for {label, val} <- [{"Unknown", "unknown"}, {"Everyone", "everyone"}, {"Teen", "teen"}, {"Teen+", "teen_plus"}, {"Mature", "mature"}, {"Adult", "adult"}, {"Explicit", "explicit"}] do %>
                    <option value={val} selected={to_string(@edit_form[:age_rating].value) == val}>
                      {label}
                    </option>
                  <% end %>
                </select>
              </div>

              <div class="col-span-2">
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Summary</label>
                <textarea
                  name="book[summary]"
                  rows="4"
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500 resize-none"
                >{@edit_form[:summary].value}</textarea>
              </div>

              <div class="col-span-2">
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Notes</label>
                <textarea
                  name="book[notes]"
                  rows="3"
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500 resize-none"
                >{@edit_form[:notes].value}</textarea>
              </div>

              <div class="col-span-2">
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Publisher</label>
                <div
                  id={"pub-picker-book-#{@book.id}"}
                  phx-hook="PublisherSearch"
                  class="relative"
                  data-publishers={Jason.encode!(Enum.map(@all_publishers, &%{id: &1.id, name: &1.name}))}
                  data-selected-ids={Jason.encode!(Enum.map(@book.publishers, & &1.id))}
                  data-input-name="book[publisher_ids][]"
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
