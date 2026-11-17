# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.TextReaderLive do
  @moduledoc """
  Reader for text books (see `Stashix.Library.text_book_file/2`); for now
  PDFs, drawn in the browser by PDF.js from byte ranges of the file (the
  `PdfReader` hook). Comics and scans stay in `StashixWeb.ReaderLive`, which
  sends text books here.

  The hook owns the pages; this view owns the chrome (bars, View menu,
  contents and search panel, end card) and progress. Commands go to the hook
  as `pdf:*` events, and it reports the page it shows back.
  """
  use StashixWeb, :live_view

  alias Stashix.{Accounts, Formatters, Library, Slug}
  alias StashixWeb.Live.CanonicalUrl
  alias StashixWeb.ReaderLive

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @progress_debounce_ms 2_000
  @layouts ~w(scroll paged spread)
  @fits ~w(width page)
  @themes ~w(paper sepia night)

  @impl true
  def mount(%{"id" => param} = params, _session, socket) do
    id = Slug.resolve!(Stashix.Library.Book, param)
    book = Library.get_book!(socket.assigns.access, id) |> Stashix.Repo.preload([:files, :series])
    format = params["format"] && String.to_existing_atom(params["format"])

    case Library.text_book_file(book, format) do
      nil ->
        # Opens as pages after all (override changed, file gone): comic reader.
        {:ok, push_navigate(socket, to: ~p"/read/#{param}?#{Map.take(params, ["page"])}", replace: true)}

      book_file ->
        {:ok, mount_text(socket, book, book_file, params), layout: false}
    end
  end

  defp mount_text(socket, book, book_file, params) do
    user = socket.assigns.current_user
    progress = Library.get_progress(user.id, book.id)

    current_page =
      case params["page"] do
        "0" -> 0
        _ -> (progress && progress.current_page) || 0
      end

    {_prev, next_book} = Library.get_adjacent_books(socket.assigns.access, book)
    settings = user.reader_settings || %{}

    socket
    |> CanonicalUrl.attach(:book)
    |> assign(
      page_title: gettext("Reading: %{title}", title: book.title),
      book: book,
      file_url: ~p"/api/books/#{book.id}/file?#{[format: book_file.format]}",
      page_count: book.page_count,
      current_page: current_page,
      loaded: false,
      failed: false,
      at_end: false,
      next_book: next_book,
      volume_counts: Library.series_volume_counts(socket.assigns.access, book),
      next_href: next_book && next_href(user.id, next_book),
      view_layout: setting(settings, "text_layout", @layouts),
      fit: setting(settings, "text_fit", @fits),
      theme: setting(settings, "text_theme", @themes),
      data_saver: Accounts.User.ui_setting(user, "data_saver") == "on",
      overlay_visible: true,
      panel: nil,
      outline: nil,
      search_query: "",
      search_results: [],
      search_scanned: 0,
      search_done: true,
      save_timer: nil
    )
  end

  defp setting(settings, key, [default | _] = allowed) do
    if settings[key] in allowed, do: settings[key], else: default
  end

  ## Events from the hook

  @impl true
  def handle_event("pdf_loaded", %{"page_count" => count}, socket) when is_integer(count) and count > 0 do
    book = sync_page_count(socket.assigns.book, count)
    {:noreply, assign(socket, book: book, page_count: count, loaded: true)}
  end

  def handle_event("pdf_failed", _params, socket), do: {:noreply, assign(socket, failed: true)}

  def handle_event("pdf_outline", %{"items" => items}, socket) when is_list(items) do
    outline =
      for %{"title" => title, "depth" => depth} = item <- items,
          is_binary(title) and is_integer(depth),
          do: %{title: title, depth: min(depth, 6), page: if(is_integer(item["page"]), do: item["page"])}

    {:noreply, assign(socket, :outline, outline)}
  end

  def handle_event("page_changed", %{"page" => page}, socket) when is_integer(page) do
    page = clamp(page, socket.assigns.page_count)

    if page == socket.assigns.current_page do
      {:noreply, socket}
    else
      # In the paged layouts a page turn back from the end card closes it.
      at_end = socket.assigns.at_end and socket.assigns.view_layout == "scroll"
      {:noreply, socket |> assign(current_page: page, at_end: at_end) |> schedule_progress_save()}
    end
  end

  # Scroll layout: the space below the last page scrolled into or out of view.
  def handle_event("scroll_end", %{"visible" => true}, %{assigns: %{at_end: false, loaded: true}} = socket),
    do: {:noreply, show_end(socket)}

  def handle_event("scroll_end", %{"visible" => false}, socket), do: {:noreply, assign(socket, :at_end, false)}
  def handle_event("scroll_end", _params, socket), do: {:noreply, socket}

  # Paged layouts: turning past the last page shows the end card; turning on
  # from there carries on into the next book.
  def handle_event("paged_end", _params, %{assigns: %{at_end: true, next_href: href}} = socket) when href != nil,
    do: {:noreply, push_navigate(socket, to: href, replace: true)}

  def handle_event("paged_end", _params, %{assigns: %{at_end: false}} = socket), do: {:noreply, show_end(socket)}
  def handle_event("paged_end", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_overlay", _params, socket),
    do: {:noreply, assign(socket, :overlay_visible, !socket.assigns.overlay_visible)}

  def handle_event("set_overlay", %{"visible" => visible}, socket) when is_boolean(visible),
    do: {:noreply, assign(socket, :overlay_visible, visible)}

  def handle_event("pdf_search_results", %{"query" => query} = params, socket) do
    if query == socket.assigns.search_query do
      results =
        for %{"page" => page, "before" => b, "match" => m, "after" => a} <- params["results"] || [],
            is_integer(page),
            do: %{page: page, before: b, match: m, after: a}

      {:noreply,
       assign(socket,
         search_results: socket.assigns.search_results ++ results,
         search_scanned: params["scanned"] || 0,
         search_done: params["done"] == true
       )}
    else
      {:noreply, socket}
    end
  end

  ## Events from the chrome

  # Slider, contents and search results: jump to a page.
  def handle_event("goto_page", %{"page" => page} = params, socket) do
    page = clamp(to_int(page), socket.assigns.page_count)
    event = if params["hit"], do: %{page: page, query: socket.assigns.search_query}, else: %{page: page}

    {:noreply, socket |> assign(:at_end, false) |> push_event("pdf:goto", event)}
  end

  def handle_event("step", %{"by" => by}, socket), do: {:noreply, push_event(socket, "pdf:step", %{by: to_int(by)})}
  def handle_event("zoom", %{"by" => by}, socket), do: {:noreply, push_event(socket, "pdf:zoom", %{by: to_int(by)})}

  def handle_event("set_layout", %{"layout" => layout}, socket) when layout in @layouts,
    do: {:noreply, socket |> assign(view_layout: layout, at_end: false) |> view_changed()}

  def handle_event("set_fit", %{"fit" => fit}, socket) when fit in @fits,
    do: {:noreply, socket |> assign(:fit, fit) |> view_changed()}

  def handle_event("set_page_theme", %{"theme" => theme}, socket) when theme in @themes,
    do: {:noreply, socket |> assign(:theme, theme) |> view_changed()}

  def handle_event("open_panel", %{"panel" => panel}, socket) when panel in ["contents", "search"] do
    panel = if socket.assigns.panel == panel, do: nil, else: panel
    {:noreply, assign(socket, panel: panel, overlay_visible: true)}
  end

  def handle_event("close_panel", _params, socket), do: {:noreply, assign(socket, :panel, nil)}

  def handle_event("search", %{"q" => query}, socket) do
    query = String.trim(query)

    if query == socket.assigns.search_query do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(search_query: query, search_results: [], search_scanned: 0, search_done: query == "")
       |> push_event("pdf:search", %{query: query})}
    end
  end

  # Leaving is an event rather than a plain link so the pending save lands
  # first (see ReaderLive).
  def handle_event("exit", %{"to" => to}, socket) when to in ["book", "series"] do
    book = socket.assigns.book
    path = if to == "series" and book.series_id, do: ~p"/series/#{book.series}", else: ~p"/book/#{book}"
    {:noreply, socket |> flush_progress() |> push_event("reader:exit", %{to: path})}
  end

  # The end card's keyboard hints are the comic reader's; here the hook owns
  # the keys, so these come only from the card's own buttons.
  def handle_event(event, _params, socket) when event in ["prev_page", "next_page"], do: {:noreply, socket}

  @impl true
  def handle_info(:save_progress, socket), do: {:noreply, save_progress(socket)}
  def handle_info({:scan_progress, _}, socket), do: {:noreply, socket}
  def handle_info({:book_added, _}, socket), do: {:noreply, socket}
  def handle_info({:cover_updated, _}, socket), do: {:noreply, socket}

  ## Helpers

  defp view_changed(socket) do
    %{view_layout: layout, fit: fit, theme: theme} = socket.assigns

    Accounts.save_reader_settings(socket.assigns.current_user, %{
      "text_layout" => layout,
      "text_fit" => fit,
      "text_theme" => theme
    })

    push_event(socket, "pdf:view", %{layout: layout, fit: fit, theme: theme})
  end

  defp clamp(page, count), do: page |> max(0) |> min(max(count - 1, 0))

  defp to_int(n) when is_integer(n), do: n

  defp to_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp to_int(_), do: 0

  defp schedule_progress_save(socket) do
    if socket.assigns.save_timer, do: Process.cancel_timer(socket.assigns.save_timer)
    assign(socket, :save_timer, Process.send_after(self(), :save_progress, @progress_debounce_ms))
  end

  defp save_progress(socket) do
    %{current_page: page, access: access, current_user: user, book: book} = socket.assigns
    if page > 0, do: Library.update_progress(access, user.id, book.id, page)
    assign(socket, :save_timer, nil)
  end

  defp flush_progress(%{assigns: %{save_timer: nil}} = socket), do: socket

  defp flush_progress(socket) do
    Process.cancel_timer(socket.assigns.save_timer)
    save_progress(socket)
  end

  # Reaching the end means the book is finished: saved now, not on the debounce.
  defp show_end(socket) do
    if socket.assigns.save_timer, do: Process.cancel_timer(socket.assigns.save_timer)
    %{access: access, current_user: user, book: book, page_count: count} = socket.assigns
    Library.update_progress(access, user.id, book.id, count - 1)
    assign(socket, at_end: true, save_timer: nil)
  end

  defp sync_page_count(book, count) when book.page_count != count do
    case Library.update_book(book, %{page_count: count}) do
      {:ok, updated} -> %{updated | series: book.series, files: book.files}
      _ -> book
    end
  end

  defp sync_page_count(book, _count), do: book

  defp next_href(user_id, next_book) do
    progress = Library.get_progress(user_id, next_book.id)
    finished = progress && next_book.page_count > 0 && progress.current_page >= next_book.page_count - 1
    if finished, do: ~p"/read/#{slug_param(next_book)}?page=0", else: ~p"/read/#{slug_param(next_book)}"
  end

  defp slider_fill(_page, count) when count <= 1, do: 100
  defp slider_fill(page, count), do: Float.round(page / (count - 1) * 100, 2)

  defp layout_icon("paged"), do: "lucide-rectangle-vertical"
  defp layout_icon("spread"), do: "lucide-columns-2"
  defp layout_icon(_scroll), do: "lucide-gallery-vertical-end"

  defp layouts do
    [{"scroll", gettext("Scroll")}, {"paged", gettext("One page")}, {"spread", gettext("Two pages")}]
  end

  defp fits do
    [{"width", gettext("Fit width"), "lucide-move-horizontal"}, {"page", gettext("Fit page"), "lucide-scan"}]
  end

  defp themes do
    [
      {"paper", gettext("Paper"), "lucide-sun"},
      {"sepia", gettext("Sepia"), "lucide-coffee"},
      {"night", gettext("Night"), "lucide-moon"}
    ]
  end

  ## Render

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      html, body { margin: 0; padding: 0; height: 100%; overflow: hidden; }
      /* Dark in every theme, like the comic reader. */
      html { background: #000; }
    </style>
    <div class="scheme-dark relative bg-black text-fg overflow-hidden" style="height: 100dvh;" id="text-reader">
      <%!-- Top bar --%>
      <div
        class={[
          "reader-bar reader-bar-top absolute top-0 left-0 right-0 z-30 flex items-center gap-2 sm:gap-3 px-3 sm:px-4 transition-transform duration-200",
          if(@overlay_visible, do: "translate-y-0", else: "-translate-y-full")
        ]}
        style="height: 48px;"
      >
        <button
          phx-click="exit"
          phx-value-to="book"
          title={gettext("Close reader")}
          class="group flex items-center gap-1.5 h-8 pl-1.5 pr-2.5 rounded-md text-muted hover:text-fg hover:bg-fg/10 font-display font-bold uppercase tracking-wide transition-colors whitespace-nowrap"
        >
          <.icon name="lucide-x" class="w-4 h-4 transition-transform group-hover:rotate-90" />
          <span class="hidden sm:inline">{gettext("Close")}</span>
        </button>

        <div class="flex-1 min-w-0 flex items-center justify-center gap-2.5">
          <.sticker :if={lbl = Formatters.book_number_label(@book, @volume_counts)} class="flex-shrink-0">{lbl}</.sticker>
          <span class="truncate font-display font-extrabold uppercase tracking-wide text-lg leading-none text-fg">
            {@book.title}
          </span>
        </div>

        <div class="flex items-center gap-2 flex-shrink-0">
          <.segmented>
            <.segment
              icon="lucide-list"
              title={gettext("Contents")}
              active={@panel == "contents"}
              phx-click="open_panel"
              phx-value-panel="contents"
            />
            <.segment
              icon="lucide-search"
              title={gettext("Search")}
              active={@panel == "search"}
              phx-click="open_panel"
              phx-value-panel="search"
            />
          </.segmented>

          <.ink_menu id="text-view-menu" modal panel_class="w-60" class="ink-segmented group">
            <:trigger
              title={gettext("View options")}
              class={[segment_class(false), "gap-1.5 px-2.5 group-data-[open]:bg-violet-600! group-data-[open]:text-white!"]}
            >
              <.icon name={layout_icon(@view_layout)} class="w-4 h-4 flex-shrink-0" />
              <span class="hidden md:inline font-display font-bold uppercase tracking-wide text-sm">{gettext("View")}</span>
              <.icon
                name="lucide-chevron-down"
                class="w-3 h-3 flex-shrink-0 transition-transform group-data-[open]:rotate-180"
              />
            </:trigger>

            <.menu_label>{gettext("Layout")}</.menu_label>
            <.menu_item
              :for={{layout, label} <- layouts()}
              icon={layout_icon(layout)}
              active={@view_layout == layout}
              phx-click="set_layout"
              phx-value-layout={layout}
            >
              {label}
            </.menu_item>

            <.menu_label class="mt-2">{gettext("Fit")}</.menu_label>
            <.menu_item
              :for={{fit, label, icon} <- fits()}
              icon={icon}
              active={@fit == fit}
              phx-click="set_fit"
              phx-value-fit={fit}
            >
              {label}
            </.menu_item>

            <.menu_label class="mt-2">{gettext("Page")}</.menu_label>
            <.menu_item
              :for={{theme, label, icon} <- themes()}
              icon={icon}
              active={@theme == theme}
              phx-click="set_page_theme"
              phx-value-theme={theme}
            >
              {label}
            </.menu_item>
          </.ink_menu>

          <p class="min-w-[3.25rem] text-right tabular-nums leading-none whitespace-nowrap">
            <%= if @at_end do %>
              <span class="font-display font-black uppercase tracking-wide text-xl text-ink">{gettext("End")}</span>
            <% else %>
              <span class="font-display font-black text-xl text-fg">{@current_page + 1}</span>
              <span class="text-muted text-xs"> / {@page_count}</span>
            <% end %>
          </p>
        </div>
      </div>

      <%!-- Pages: the hook's. phx-update="ignore" keeps patches off its
           canvases; its attributes are still patched, so every data-* the
           hook also sets is rendered here too. From `sm` up the open panel
           pushes the pages aside (the hook re-fits on the resize). --%>
      <div class={["absolute inset-0", @panel && "sm:left-80"]}>
        <div
          id="pdf-reader"
          class="pdf-scroller"
          phx-hook="PdfReader"
          phx-update="ignore"
          tabindex="-1"
          data-url={@file_url}
          data-start={@current_page}
          data-layout={@view_layout}
          data-fit={@fit}
          data-page-theme={@theme}
          data-saver={to_string(@data_saver)}
          data-overlay={to_string(@overlay_visible)}
        >
          <div class="pdf-column" data-pdf-pages></div>
          <div class="pdf-end" data-pdf-end></div>
        </div>
      </div>

      <div :if={!@loaded} class="absolute inset-0 z-10 flex items-center justify-center pointer-events-none">
        <%= if @failed do %>
          <p class="px-3 py-1.5 bg-ink text-zinc-950 text-sm font-semibold">{gettext("This PDF could not be opened.")}</p>
        <% else %>
          <.icon name="lucide-loader-circle" class="animate-spin h-8 w-8 text-ink/50" />
        <% end %>
      </div>

      <%!-- Floating zoom controls --%>
      <div
        class={[
          "absolute transition-transform duration-200",
          if(@overlay_visible, do: "translate-x-0", else: "translate-x-[calc(100%+16px)]")
        ]}
        style="top: 64px; right: 16px; z-index: 25;"
      >
        <.segmented vertical class="reader-ctl-float">
          <.segment icon="lucide-plus" title={gettext("Zoom in (+)")} phx-click="zoom" phx-value-by="1" />
          <.segment icon="lucide-minus" title={gettext("Zoom out (-)")} phx-click="zoom" phx-value-by="-1" />
          <.segment icon="lucide-scan" title={gettext("Reset zoom (0)")} phx-click="zoom" phx-value-by="0" />
        </.segmented>
      </div>

      <.side_panel
        :if={@panel}
        panel={@panel}
        outline={@outline}
        current_page={@current_page}
        query={@search_query}
        results={@search_results}
        scanned={@search_scanned}
        done={@search_done}
        page_count={@page_count}
      />

      <ReaderLive.end_card
        :if={@at_end}
        book={@book}
        next_book={@next_book}
        next_href={@next_href}
        volume_counts={@volume_counts}
      />

      <%!-- Bottom bar: scrubber --%>
      <div class={[
        "reader-bar reader-bar-bottom absolute bottom-0 left-0 right-0 z-30 px-4 py-2.5 transition-transform duration-200",
        if(@overlay_visible, do: "translate-y-0", else: "translate-y-full")
      ]}>
        <div class="flex items-center gap-4">
          <span class="w-10 text-right font-display font-black text-xl leading-none text-fg tabular-nums">
            {@current_page + 1}
          </span>
          <input
            id="page-slider"
            type="range"
            min="0"
            max={max(@page_count - 1, 0)}
            value={@current_page}
            phx-hook="PageSlider"
            aria-label={gettext("Page")}
            class="reader-slider flex-1"
            style={"--fill: #{slider_fill(@current_page, @page_count)}%"}
          />
          <span class="w-10 font-display font-bold text-base leading-none text-muted tabular-nums">{@page_count}</span>
        </div>
      </div>
    </div>
    """
  end

  attr :panel, :string, required: true
  attr :outline, :list, default: nil
  attr :current_page, :integer, required: true
  attr :query, :string, required: true
  attr :results, :list, required: true
  attr :scanned, :integer, required: true
  attr :done, :boolean, required: true
  attr :page_count, :integer, required: true

  # Contents and search, one panel with two tabs: on the left from `sm` up, a
  # bottom sheet on phones so the page an entry jumps to shows above it.
  defp side_panel(assigns) do
    assigns = assign(assigns, :current_entry, current_entry(assigns.outline, assigns.current_page))

    ~H"""
    <aside
      id="text-reader-panel"
      class="absolute z-40 inset-x-0 bottom-0 top-[45dvh] sm:top-12 sm:right-auto sm:w-80 flex flex-col bg-zinc-950/95 backdrop-blur-md ring-1 ring-fg/10"
      aria-label={gettext("Contents and search")}
    >
      <div class="flex items-center gap-1 px-2 pt-2 border-b border-fg/10">
        <button
          :for={{tab, label} <- [{"contents", gettext("Contents")}, {"search", gettext("Search")}]}
          phx-click="open_panel"
          phx-value-panel={tab}
          disabled={@panel == tab}
          class={[
            "px-3 py-2 -mb-px border-b-2 font-display font-bold uppercase tracking-wide text-sm transition-colors",
            if(@panel == tab, do: "border-ink text-fg", else: "border-transparent text-muted hover:text-fg")
          ]}
        >
          {label}
        </button>
        <button
          phx-click="close_panel"
          title={gettext("Close")}
          class="ml-auto p-1.5 rounded-md text-muted hover:text-fg hover:bg-fg/10"
        >
          <.icon name="lucide-x" class="w-4 h-4" />
        </button>
      </div>

      <div :if={@panel == "contents"} class="flex-1 overflow-y-auto overscroll-contain py-2">
        <%= cond do %>
          <% @outline == nil -> %>
            <p class="px-4 py-3 text-sm text-muted">{gettext("Reading the contents…")}</p>
          <% @outline == [] -> %>
            <p class="px-4 py-3 text-sm text-muted">{gettext("This PDF has no table of contents.")}</p>
          <% true -> %>
            <ol>
              <li :for={{entry, i} <- Enum.with_index(@outline)}>
                <button
                  :if={entry.page}
                  phx-click="goto_page"
                  phx-value-page={entry.page}
                  class={[
                    "w-full flex items-baseline gap-3 pr-4 py-1.5 text-left text-sm border-l-2 transition-colors hover:bg-fg/10",
                    if(i == @current_entry, do: "border-ink text-fg", else: "border-transparent text-fg-soft")
                  ]}
                  style={"padding-left: #{1 + entry.depth}rem"}
                >
                  <span class="flex-1 min-w-0">{entry.title}</span>
                  <span class="text-xs text-muted tabular-nums">{entry.page + 1}</span>
                </button>
                <p :if={!entry.page} class="pr-4 py-1.5 text-sm text-muted" style={"padding-left: #{1 + entry.depth}rem"}>
                  {entry.title}
                </p>
              </li>
            </ol>
        <% end %>
      </div>

      <div :if={@panel == "search"} class="flex-1 min-h-0 flex flex-col">
        <form phx-change="search" phx-submit="search" class="p-3">
          <input
            type="search"
            name="q"
            value={@query}
            phx-debounce="400"
            autocomplete="off"
            autofocus
            placeholder={gettext("Search this book")}
            aria-label={gettext("Search this book")}
            class="w-full h-9 px-3 rounded-md bg-fg/5 ring-1 ring-fg/15 text-sm text-fg placeholder:text-muted focus:outline-none focus:ring-ink"
          />
        </form>
        <p :if={@query != ""} class="px-4 pb-2 text-xs text-muted" aria-live="polite">
          <%= if @done do %>
            <%= if length(@results) >= 500 do %>
              {gettext("The first %{count} matches", count: length(@results))}
            <% else %>
              {ngettext("1 match", "%{count} matches", length(@results))}
            <% end %>
          <% else %>
            {gettext("Searching… page %{page} of %{count}", page: @scanned, count: @page_count)}
          <% end %>
        </p>
        <ol class="flex-1 overflow-y-auto overscroll-contain pb-2">
          <li :for={hit <- @results}>
            <button
              phx-click="goto_page"
              phx-value-page={hit.page}
              phx-value-hit={true}
              class="w-full flex items-baseline gap-3 px-4 py-2 text-left text-sm text-fg-soft hover:bg-fg/10 transition-colors"
            >
              <span class="flex-1 min-w-0 line-clamp-2">
                {hit.before}<mark class="bg-ink/30 text-fg rounded-sm">{hit.match}</mark>{hit.after}
              </span>
              <span class="text-xs text-muted tabular-nums">{hit.page + 1}</span>
            </button>
          </li>
        </ol>
      </div>
    </aside>
    """
  end

  # The last contents entry at or before the current page.
  defp current_entry(nil, _page), do: nil

  defp current_entry(outline, page) do
    outline
    |> Enum.with_index()
    |> Enum.filter(fn {entry, _i} -> entry.page != nil and entry.page <= page end)
    |> Enum.max_by(fn {entry, i} -> {entry.page, i} end, fn -> {nil, nil} end)
    |> elem(1)
  end
end
