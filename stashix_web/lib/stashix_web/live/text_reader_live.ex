# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.TextReaderLive do
  @moduledoc """
  Reader for text books (see `Stashix.Library.text_book_file/2`). Comics
  and scans stay in `StashixWeb.ReaderLive`, which sends text books here.

  - PDF: drawn by PDF.js from byte ranges of the file (the `PdfReader`
    hook). Progress is the PDF page.
  - EPUB: laid out by foliate-js from entries fetched one at a time (the
    `EpubReader` hook). Progress is foliate-js locations (about 1500 bytes
    of text each), which the scanner also counts as the book's pages.
  - Kindle (MOBI, AZW3) and FictionBook: the same hook and foliate-js, from
    byte ranges of the file (FB2: the whole XML). DRM-protected books
    don't open; the view says so instead.

  `engine` is which of the two hooks reads the book: `:pdf` or `:foliate`.

  The hook owns the content; this view owns the chrome (bars, View menu,
  contents and search panel, end card) and progress. Both hooks take the same
  `text:*` commands and report back with the same events. Book content is
  untrusted: the route sets a strict CSP (`StashixWeb.Plugs.ReaderCSP`).
  """
  use StashixWeb, :live_view

  alias Stashix.{Accounts, Formatters, Library, Slug}
  alias StashixWeb.Live.{CanonicalUrl, ReaderAnnotations}
  alias StashixWeb.ReaderLive

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @progress_debounce_ms 2_000
  @layouts ~w(scroll paged spread)
  @epub_layouts ~w(paged scroll)
  @fits ~w(width page)
  @themes ~w(paper sepia night)
  @fonts ~w(original serif sans)
  @spacings ~w(normal tight loose)
  @margins ~w(normal narrow wide)
  @text_sizes [80, 90, 100, 110, 120, 135, 150, 175, 200]
  @panels ~w(contents search notes)
  @annotation_events ~w(annotate annotation_color annotation_edit annotation_note annotation_cancel annotation_delete)

  @impl true
  def mount(%{"id" => param} = params, _session, socket) do
    id = Slug.resolve!(Stashix.Library.Book, param)
    book = Library.get_book!(socket.assigns.access, id) |> Stashix.Repo.preload([:files, :series])
    format = params["format"] && String.to_existing_atom(params["format"])

    case Library.text_book_file(book, format) do
      nil ->
        # Opens as pages after all (override changed, file gone): comic reader.
        {:ok, push_navigate(socket, to: ~p"/read/#{param}?#{Map.take(params, ["page", "at"])}", replace: true)}

      book_file ->
        {:ok, mount_text(socket, book, book_file, params), layout: false}
    end
  end

  defp mount_text(socket, book, book_file, params) do
    user = socket.assigns.current_user
    progress = Library.get_progress(user.id, book.id)

    # ?page=0 starts over; ?at=<annotation> opens at one of the user's
    # highlights; else resume where the server has this reader.
    progress = if params["page"] == "0", do: nil, else: progress
    {current_page, start_cfi} = start_at(user, book, book_file.format, params["at"], progress)

    {_prev, next_book} = Library.get_adjacent_books(socket.assigns.access, book)
    settings = user.reader_settings || %{}

    engine = if book_file.format == :pdf, do: :pdf, else: :foliate
    drm? = Stashix.Media.Formats.mobi?(book_file.format) and Stashix.Media.Mobi.drm?(book_file.path)

    socket
    |> CanonicalUrl.attach(:book)
    |> assign(
      page_title: gettext("Reading: %{title}", title: book.title),
      book: book,
      format: book_file.format,
      engine: engine,
      file_url:
        if(book_file.format == :epub,
          do: ~p"/api/books/#{book.id}/epub",
          else: ~p"/api/books/#{book.id}/file?#{[format: book_file.format]}"
        ),
      page_count: book.page_count,
      current_page: current_page,
      # Fixed at mount: the hook only reads it to open the book there.
      start_cfi: start_cfi,
      locator: nil,
      progression: nil,
      loaded: false,
      # :drm when the book is locked; true when the hook couldn't open it.
      failed: if(drm?, do: :drm, else: false),
      at_end: false,
      next_book: next_book,
      volume_counts: Library.series_volume_counts(socket.assigns.access, book),
      next_href: next_book && next_href(user.id, next_book),
      view_layout:
        if(engine == :foliate,
          do: setting(settings, "epub_layout", @epub_layouts),
          else: setting(settings, "text_layout", @layouts)
        ),
      fit: setting(settings, "text_fit", @fits),
      theme: setting(settings, "text_theme", @themes),
      font: setting(settings, "epub_font", @fonts),
      spacing: setting(settings, "epub_spacing", @spacings),
      margins: setting(settings, "epub_margins", @margins),
      text_size: if(settings["epub_size"] in @text_sizes, do: settings["epub_size"], else: 100),
      current_target: nil,
      data_saver: Accounts.User.ui_setting(user, "data_saver") == "on",
      overlay_visible: true,
      panel: nil,
      outline: nil,
      search_query: "",
      search_results: [],
      search_scanned: 0,
      search_done: true,
      save_timer: nil,
      # The bookmark at the spot showing, if any (EPUB: the hook says).
      bookmark_here: nil
    )
    |> ReaderAnnotations.init()
  end

  defp setting(settings, key, [default | _] = allowed) do
    if settings[key] in allowed, do: settings[key], else: default
  end

  ## Events from the hook

  @impl true
  def handle_event("loaded", %{"page_count" => count}, socket) when is_integer(count) and count > 0 do
    book = sync_page_count(socket.assigns.book, count)

    {:noreply,
     socket |> assign(book: book, page_count: count, loaded: true) |> ReaderAnnotations.push_all() |> pdf_bookmark()}
  end

  def handle_event("failed", _params, socket), do: {:noreply, assign(socket, failed: true)}

  # Entries point at a PDF page, or (EPUB) at an href inside the book.
  def handle_event("outline", %{"items" => items}, socket) when is_list(items) do
    outline =
      for %{"title" => title, "depth" => depth} = item <- items,
          is_binary(title) and is_integer(depth),
          do: %{
            title: title,
            depth: min(depth, 6),
            page: int_or_nil(item["page"]),
            target: string_or_nil(item["target"])
          }

    {:noreply, assign(socket, :outline, outline)}
  end

  # EPUB: the location comes with the total (fixed once the book is open) and
  # the contents entry it falls under.
  def handle_event("page_changed", %{"page" => page} = params, socket) when is_integer(page) do
    socket =
      case params["total"] do
        total when is_integer(total) and total > 0 and total != socket.assigns.page_count ->
          assign(socket, book: sync_page_count(socket.assigns.book, total), page_count: total)

        _ ->
          socket
      end

    socket = assign(socket, :current_target, string_or_nil(params["toc"]) || socket.assigns.current_target)
    page = clamp(page, socket.assigns.page_count)
    locator = locator(socket.assigns.format, page, params)
    moved? = locator != socket.assigns.locator
    socket = assign(socket, locator: locator, progression: fraction(params))

    if page == socket.assigns.current_page and not moved? do
      {:noreply, socket}
    else
      # In the paged layouts a page turn back from the end card closes it.
      at_end = socket.assigns.at_end and socket.assigns.view_layout == "scroll"
      {:noreply, socket |> assign(current_page: page, at_end: at_end) |> pdf_bookmark() |> schedule_progress_save()}
    end
  end

  ## Annotations (see `StashixWeb.Live.ReaderAnnotations`)

  def handle_event(event, params, socket) when event in @annotation_events do
    case ReaderAnnotations.handle_event(event, params, socket, &annotation_locator(socket, &1), nil) do
      :unhandled -> {:noreply, socket}
      {:reply, reply, socket} -> {:reply, reply, pdf_bookmark(socket)}
      {:noreply, socket} -> {:noreply, pdf_bookmark(socket)}
    end
  end

  def handle_event("annotation_goto", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.annotations, &(&1.id == id)) do
      %{locator: %{"cfi" => cfi}} -> handle_event("goto_target", %{"target" => cfi}, socket)
      %{locator: %{"page" => page}} -> handle_event("goto_page", %{"page" => page}, socket)
      _ -> {:noreply, socket}
    end
  end

  # The bookmark button: drops the bookmark showing, or bookmarks the spot.
  def handle_event("toggle_bookmark", _params, %{assigns: %{bookmark_here: id}} = socket) when is_binary(id) do
    {:noreply, socket} = handle_event("annotation_delete", %{"id" => id}, socket)
    {:noreply, assign(socket, :bookmark_here, nil)}
  end

  def handle_event("toggle_bookmark", _params, %{assigns: %{locator: locator}} = socket) when is_map(locator) do
    params = Map.merge(locator, %{"kind" => "bookmark", "fraction" => socket.assigns.progression})

    case handle_event("annotate", params, socket) do
      {:reply, %{item: %{id: id}}, socket} -> {:noreply, assign(socket, :bookmark_here, id)}
      {:reply, _, socket} -> {:noreply, socket}
    end
  end

  def handle_event("toggle_bookmark", _params, socket), do: {:noreply, socket}

  # EPUB: the hook knows which bookmark falls on the pages showing.
  def handle_event("bookmark_here", params, socket),
    do: {:noreply, assign(socket, :bookmark_here, string_or_nil(params["id"]))}

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

  # Hits point at a PDF page, or (EPUB) at a CFI, labelled with the chapter.
  def handle_event("search_results", %{"query" => query} = params, socket) do
    if query == socket.assigns.search_query do
      results =
        for %{"before" => b, "match" => m, "after" => a} = hit <- params["results"] || [],
            is_integer(hit["page"]) or is_binary(hit["target"]),
            do: %{
              page: int_or_nil(hit["page"]),
              target: string_or_nil(hit["target"]),
              label: string_or_nil(hit["label"]),
              before: b,
              match: m,
              after: a
            }

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

    {:noreply, socket |> assign(:at_end, false) |> push_event("text:goto", event)}
  end

  # Contents entries and search hits inside an EPUB.
  def handle_event("goto_target", %{"target" => target} = params, socket) when is_binary(target) do
    event = if params["hit"], do: %{target: target, query: socket.assigns.search_query}, else: %{target: target}
    {:noreply, socket |> assign(:at_end, false) |> push_event("text:goto", event)}
  end

  def handle_event("step", %{"by" => by}, socket), do: {:noreply, push_event(socket, "text:step", %{by: to_int(by)})}

  # EPUB: the zoom buttons change the text size instead.
  def handle_event("zoom", %{"by" => by}, %{assigns: %{engine: :foliate}} = socket) do
    size =
      case to_int(by) do
        0 -> 100
        by -> step_size(socket.assigns.text_size, by)
      end

    {:noreply, socket |> assign(:text_size, size) |> view_changed()}
  end

  def handle_event("zoom", %{"by" => by}, socket), do: {:noreply, push_event(socket, "text:zoom", %{by: to_int(by)})}

  def handle_event("set_layout", %{"layout" => layout}, socket) do
    allowed = if socket.assigns.engine == :foliate, do: @epub_layouts, else: @layouts

    if layout in allowed,
      do: {:noreply, socket |> assign(view_layout: layout, at_end: false) |> view_changed()},
      else: {:noreply, socket}
  end

  def handle_event("set_font", %{"font" => font}, socket) when font in @fonts,
    do: {:noreply, socket |> assign(:font, font) |> view_changed()}

  def handle_event("set_spacing", %{"spacing" => spacing}, socket) when spacing in @spacings,
    do: {:noreply, socket |> assign(:spacing, spacing) |> view_changed()}

  def handle_event("set_margins", %{"margins" => margins}, socket) when margins in @margins,
    do: {:noreply, socket |> assign(:margins, margins) |> view_changed()}

  def handle_event("set_fit", %{"fit" => fit}, socket) when fit in @fits,
    do: {:noreply, socket |> assign(:fit, fit) |> view_changed()}

  def handle_event("set_page_theme", %{"theme" => theme}, socket) when theme in @themes,
    do: {:noreply, socket |> assign(:theme, theme) |> view_changed()}

  def handle_event("open_panel", %{"panel" => panel}, socket) when panel in @panels do
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
       |> push_event("text:search", %{query: query})}
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

  # Hook params to a locator: a CFI (range) in a foliate book, a page and
  # its text rects in a PDF.
  defp annotation_locator(%{assigns: %{engine: :pdf}}, params),
    do: %{"type" => "pdf", "page" => params["page"], "rects" => params["rects"]}

  defp annotation_locator(socket, params) do
    %{"type" => locator_type(socket.assigns.format), "cfi" => params["cfi"], "href" => string_or_nil(params["href"])}
  end

  # PDF: a bookmark on the page showing.
  defp pdf_bookmark(%{assigns: %{engine: :pdf, current_page: page, annotations: list}} = socket) do
    here = Enum.find(list, &(&1.kind == :bookmark and &1.locator["page"] == page))
    assign(socket, :bookmark_here, here && here.id)
  end

  defp pdf_bookmark(socket), do: socket

  defp view_changed(%{assigns: %{engine: :foliate}} = socket) do
    a = socket.assigns

    Accounts.save_reader_settings(a.current_user, %{
      "epub_layout" => a.view_layout,
      "epub_font" => a.font,
      "epub_spacing" => a.spacing,
      "epub_margins" => a.margins,
      "epub_size" => a.text_size,
      "text_theme" => a.theme
    })

    push_event(socket, "text:view", epub_view(a))
  end

  defp view_changed(socket) do
    %{view_layout: layout, fit: fit, theme: theme} = socket.assigns

    Accounts.save_reader_settings(socket.assigns.current_user, %{
      "text_layout" => layout,
      "text_fit" => fit,
      "text_theme" => theme
    })

    push_event(socket, "text:view", %{layout: layout, fit: fit, theme: theme})
  end

  defp epub_view(a),
    do: %{
      layout: a.view_layout,
      theme: a.theme,
      font: a.font,
      spacing: a.spacing,
      margins: a.margins,
      size: a.text_size
    }

  defp step_size(size, by) do
    i = Enum.find_index(@text_sizes, &(&1 == size)) || 2
    Enum.at(@text_sizes, i |> Kernel.+(by) |> max(0) |> min(length(@text_sizes) - 1))
  end

  defp int_or_nil(n) when is_integer(n), do: n
  defp int_or_nil(_), do: nil

  defp string_or_nil(s) when is_binary(s) and s != "", do: s
  defp string_or_nil(_), do: nil

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

    if page > 0 do
      Library.update_progress(access, user.id, book.id, page,
        locator: socket.assigns.locator,
        progression: socket.assigns.progression
      )
    end

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
    last = max(count - 1, 0)
    # EPUB: the spot on the last page; PDF: the last page.
    locator = socket.assigns.locator || locator(socket.assigns.format, last, %{})
    Library.update_progress(access, user.id, book.id, last, progression: 1.0, locator: locator)
    assign(socket, at_end: true, save_timer: nil)
  end

  defp start_at(user, book, format, at, progress) do
    resume = {(progress && progress.current_page) || 0, start_cfi(progress, format)}

    case at && Stashix.Annotations.get(user.id, at) do
      %{book_id: id, locator: %{"cfi" => cfi, "type" => type}} when id == book.id ->
        if type == locator_type(format), do: {elem(resume, 0), cfi}, else: resume

      %{book_id: id, locator: %{"page" => page}} when id == book.id and is_integer(page) and format == :pdf ->
        {max(page, 0), nil}

      _ ->
        resume
    end
  end

  # A CFI saved by this book's format (not one from another file of the book).
  defp start_cfi(%{locator: %{"type" => type, "cfi" => cfi}}, format) when is_binary(cfi) do
    if type == locator_type(format), do: cfi
  end

  defp start_cfi(_progress, _format), do: nil

  # Where the reader is, as saved with the progress (see `Stashix.Library.ReadingProgress`).
  defp locator(:pdf, page, _params), do: %{"type" => "pdf", "page" => page}

  defp locator(format, _page, params) do
    case params["cfi"] do
      "epubcfi(" <> _ = cfi -> %{"type" => locator_type(format), "cfi" => cfi, "href" => string_or_nil(params["href"])}
      _ -> nil
    end
  end

  defp locator_type(format) do
    cond do
      Stashix.Media.Formats.mobi?(format) -> "mobi"
      Stashix.Media.Formats.fb2?(format) -> "fb2"
      true -> to_string(format)
    end
  end

  # EPUB reports how far through the book it is; PDF progress goes by page.
  defp fraction(%{"fraction" => f}) when is_number(f), do: f |> max(0.0) |> min(1.0) |> Kernel.*(1.0)
  defp fraction(_params), do: nil

  defp sync_page_count(book, count) when book.page_count != count do
    case Library.update_book(book, %{page_count: count}) do
      {:ok, updated} -> %{updated | series: book.series, files: book.files}
      _ -> book
    end
  end

  defp sync_page_count(book, _count), do: book

  defp next_href(user_id, next_book) do
    progress = Library.get_progress(user_id, next_book.id)
    finished = progress && progress.progression >= 1
    if finished, do: ~p"/read/#{slug_param(next_book)}?page=0", else: ~p"/read/#{slug_param(next_book)}"
  end

  defp slider_fill(_page, count) when count <= 1, do: 100
  defp slider_fill(page, count), do: Float.round(page / (count - 1) * 100, 2)

  defp layout_icon("paged"), do: "lucide-rectangle-vertical"
  defp layout_icon("spread"), do: "lucide-columns-2"
  defp layout_icon(_scroll), do: "lucide-gallery-vertical-end"

  defp layouts(:foliate), do: [{"paged", gettext("Pages")}, {"scroll", gettext("Scroll")}]

  defp layouts(_pdf),
    do: [{"scroll", gettext("Scroll")}, {"paged", gettext("One page")}, {"spread", gettext("Two pages")}]

  defp fonts do
    [{"original", gettext("Book's own")}, {"serif", gettext("Serif")}, {"sans", gettext("Sans serif")}]
  end

  defp spacings do
    [{"tight", gettext("Tight")}, {"normal", gettext("Normal")}, {"loose", gettext("Loose")}]
  end

  defp margins do
    [{"narrow", gettext("Narrow")}, {"normal", gettext("Normal")}, {"wide", gettext("Wide")}]
  end

  # EPUB progress reads as a share of the book; its "pages" are locations.
  defp percent(_page, count) when count <= 1, do: 0
  defp percent(page, count), do: round((page + 1) / count * 100)

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
            <.segment
              icon="lucide-notebook-pen"
              title={gettext("Notes")}
              active={@panel == "notes"}
              phx-click="open_panel"
              phx-value-panel="notes"
            />
          </.segmented>

          <.segmented>
            <.segment
              id="bookmark-toggle"
              icon={if @bookmark_here, do: "lucide-bookmark-check", else: "lucide-bookmark"}
              title={if @bookmark_here, do: gettext("Remove bookmark"), else: gettext("Bookmark this page")}
              active={@bookmark_here != nil}
              disabled={!@loaded}
              phx-click="toggle_bookmark"
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
              :for={{layout, label} <- layouts(@engine)}
              icon={layout_icon(layout)}
              active={@view_layout == layout}
              phx-click="set_layout"
              phx-value-layout={layout}
            >
              {label}
            </.menu_item>

            <%= if @engine == :foliate do %>
              <.menu_label class="mt-2">{gettext("Font")}</.menu_label>
              <.menu_item
                :for={{font, label} <- fonts()}
                active={@font == font}
                phx-click="set_font"
                phx-value-font={font}
              >
                {label}
              </.menu_item>

              <.menu_label class="mt-2">{gettext("Line spacing")}</.menu_label>
              <.menu_item
                :for={{spacing, label} <- spacings()}
                active={@spacing == spacing}
                phx-click="set_spacing"
                phx-value-spacing={spacing}
              >
                {label}
              </.menu_item>

              <.menu_label class="mt-2">{gettext("Margins")}</.menu_label>
              <.menu_item
                :for={{margins, label} <- margins()}
                active={@margins == margins}
                phx-click="set_margins"
                phx-value-margins={margins}
              >
                {label}
              </.menu_item>
            <% else %>
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
            <% end %>

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
            <%= cond do %>
              <% @at_end -> %>
                <span class="font-display font-black uppercase tracking-wide text-xl text-ink">{gettext("End")}</span>
              <% @engine == :foliate -> %>
                <span class="font-display font-black text-xl text-fg">{percent(@current_page, @page_count)}</span>
                <span class="text-muted text-xs">%</span>
              <% true -> %>
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
        <%!-- EPUB: foliate-js lays the book out inside; same rule on data-*. --%>
        <div
          :if={@engine == :foliate and @failed != :drm}
          id="epub-reader"
          class="epub-reader"
          phx-hook="EpubReader"
          phx-update="ignore"
          data-url={@file_url}
          data-format={@format}
          data-start={@current_page}
          data-cfi={@start_cfi}
          data-total={@page_count}
          data-layout={@view_layout}
          data-page-theme={@theme}
          data-font={@font}
          data-spacing={@spacing}
          data-margins={@margins}
          data-size={@text_size}
          data-overlay={to_string(@overlay_visible)}
        >
        </div>
        <div
          :if={@engine != :foliate}
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
        <%= cond do %>
          <% @failed == :drm -> %>
            <p class="max-w-sm px-3 py-1.5 bg-ink text-zinc-950 text-sm font-semibold text-center">
              {gettext("This book is DRM-protected and can't be opened here.")}
            </p>
          <% @failed -> %>
            <p class="px-3 py-1.5 bg-ink text-zinc-950 text-sm font-semibold">
              {gettext("This book could not be opened.")}
            </p>
          <% true -> %>
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
          <%= if @engine == :foliate do %>
            <.segment icon="lucide-a-arrow-up" title={gettext("Larger text (+)")} phx-click="zoom" phx-value-by="1" />
            <.segment icon="lucide-a-arrow-down" title={gettext("Smaller text (-)")} phx-click="zoom" phx-value-by="-1" />
            <.segment icon="lucide-type" title={gettext("Normal text size (0)")} phx-click="zoom" phx-value-by="0" />
          <% else %>
            <.segment icon="lucide-plus" title={gettext("Zoom in (+)")} phx-click="zoom" phx-value-by="1" />
            <.segment icon="lucide-minus" title={gettext("Zoom out (-)")} phx-click="zoom" phx-value-by="-1" />
            <.segment icon="lucide-scan" title={gettext("Reset zoom (0)")} phx-click="zoom" phx-value-by="0" />
          <% end %>
        </.segmented>
      </div>

      <.side_panel
        :if={@panel}
        panel={@panel}
        outline={@outline}
        current_page={@current_page}
        current_target={@current_target}
        engine={@engine}
        annotations={@annotations}
        editing_note={@editing_note}
        book={@book}
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
  attr :current_target, :string, default: nil
  attr :engine, :atom, required: true
  attr :annotations, :list, required: true
  attr :editing_note, :string, default: nil
  attr :book, :map, required: true
  attr :query, :string, required: true
  attr :results, :list, required: true
  attr :scanned, :integer, required: true
  attr :done, :boolean, required: true
  attr :page_count, :integer, required: true

  # Contents and search, one panel with two tabs: on the left from `sm` up, a
  # bottom sheet on phones so the page an entry jumps to shows above it.
  defp side_panel(assigns) do
    assigns =
      assign(assigns, :current_entry, current_entry(assigns.outline, assigns.current_page, assigns.current_target))

    ~H"""
    <aside
      id="text-reader-panel"
      class="absolute z-40 inset-x-0 bottom-0 top-[45dvh] sm:top-12 sm:right-auto sm:w-80 flex flex-col bg-zinc-950/95 backdrop-blur-md ring-1 ring-fg/10"
      aria-label={gettext("Contents, search and notes")}
    >
      <div class="flex items-center gap-1 px-2 pt-2 border-b border-fg/10">
        <button
          :for={
            {tab, label} <- [{"contents", gettext("Contents")}, {"search", gettext("Search")}, {"notes", gettext("Notes")}]
          }
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
            <p class="px-4 py-3 text-sm text-muted">{gettext("This book has no table of contents.")}</p>
          <% true -> %>
            <ol>
              <li :for={{entry, i} <- Enum.with_index(@outline)}>
                <button
                  :if={entry.page || entry.target}
                  phx-click={if entry.target, do: "goto_target", else: "goto_page"}
                  phx-value-page={entry.page}
                  phx-value-target={entry.target}
                  class={[
                    "w-full flex items-baseline gap-3 pr-4 py-1.5 text-left text-sm border-l-2 transition-colors hover:bg-fg/10",
                    if(i == @current_entry, do: "border-ink text-fg", else: "border-transparent text-fg-soft")
                  ]}
                  style={"padding-left: #{1 + entry.depth}rem"}
                >
                  <span class="flex-1 min-w-0">{entry.title}</span>
                  <span :if={entry.page} class="text-xs text-muted tabular-nums">{entry.page + 1}</span>
                </button>
                <p
                  :if={!entry.page && !entry.target}
                  class="pr-4 py-1.5 text-sm text-muted"
                  style={"padding-left: #{1 + entry.depth}rem"}
                >
                  {entry.title}
                </p>
              </li>
            </ol>
        <% end %>
      </div>

      <ReaderAnnotations.notes_list
        :if={@panel == "notes"}
        annotations={@annotations}
        editing_note={@editing_note}
        book={@book}
      />

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
            <%= if @engine == :foliate do %>
              {gettext("Searching…")}
            <% else %>
              {gettext("Searching… page %{page} of %{count}", page: @scanned, count: @page_count)}
            <% end %>
          <% end %>
        </p>
        <ol class="flex-1 overflow-y-auto overscroll-contain pb-2">
          <li :for={hit <- @results}>
            <button
              phx-click={if hit.target, do: "goto_target", else: "goto_page"}
              phx-value-page={hit.page}
              phx-value-target={hit.target}
              phx-value-hit={true}
              class="w-full flex items-baseline gap-3 px-4 py-2 text-left text-sm text-fg-soft hover:bg-fg/10 transition-colors"
            >
              <span class="flex-1 min-w-0 line-clamp-2">
                {hit.before}<mark class="bg-ink/30 text-fg rounded-sm">{hit.match}</mark>{hit.after}
              </span>
              <span :if={hit.page} class="text-xs text-muted tabular-nums">{hit.page + 1}</span>
              <span :if={!hit.page && hit.label} class="max-w-[6rem] truncate text-xs text-muted">{hit.label}</span>
            </button>
          </li>
        </ol>
      </div>
    </aside>
    """
  end

  # EPUB: the entry the hook says the reader is in. PDF: the last entry at or
  # before the current page.
  defp current_entry(nil, _page, _target), do: nil

  defp current_entry(outline, _page, target) when is_binary(target),
    do: Enum.find_index(outline, &(&1.target == target))

  defp current_entry(outline, page, nil) do
    outline
    |> Enum.with_index()
    |> Enum.filter(fn {entry, _i} -> entry.page != nil and entry.page <= page end)
    |> Enum.max_by(fn {entry, i} -> {entry.page, i} end, fn -> {nil, nil} end)
    |> elem(1)
  end
end
