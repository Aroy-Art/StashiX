defmodule StashixWeb.ReaderLive do
  use StashixWeb, :live_view

  alias Stashix.{Accounts, Library, Media.Extractor}

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @progress_debounce_ms 2_000

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    book = Library.get_book!(socket.assigns.access, id) |> Stashix.Repo.preload([:files, :series])
    format = params["format"] && String.to_existing_atom(params["format"])
    book_file = Library.get_preferred_book_file(book, format)

    pages =
      if book_file do
        case Extractor.list_pages(book_file.path) do
          {:ok, p} -> p
          _ -> []
        end
      else
        []
      end

    book = sync_page_count(book, length(pages))
    book_format = book_file && to_string(book_file.format)

    user = socket.assigns.current_user
    progress = Library.get_progress(user.id, id)

    current_page =
      case Map.get(params, "page") do
        "0" -> 0
        _ -> (progress && progress.current_page) || 0
      end

    {_prev_book, next_book} = Library.get_adjacent_books(socket.assigns.access, book)

    settings = user.reader_settings || %{}
    page_layout = Map.get(settings, "page_layout", "single")
    direction = Map.get(settings, "direction", "ltr")
    fit_mode = Map.get(settings, "fit_mode", "page")

    {:ok,
     assign(socket,
       page_title: "Reading: #{book.title}",
       book: book,
       book_format: book_format,
       pages: pages,
       page_count: length(pages),
       current_page: current_page,
       at_end: false,
       next_book: next_book,
       next_href: next_book && next_href(user.id, next_book),
       page_layout: page_layout,
       direction: direction,
       fit_mode: fit_mode,
       layout_menu_open: false,
       overlay_visible: true,
       save_timer: nil
     ), layout: false}
  end

  @impl true
  # The end card sits one step past the last page; stepping back just closes it.
  def handle_event("prev_page", _params, %{assigns: %{at_end: true}} = socket) do
    {:noreply, assign(socket, :at_end, false)}
  end

  def handle_event("prev_page", _params, socket) do
    step = prev_step(socket.assigns.page_layout, socket.assigns.current_page)
    new_page = max(socket.assigns.current_page - step, 0)
    {:noreply, socket |> assign(:current_page, new_page) |> schedule_progress_save()}
  end

  # Paging forward again from the end card carries straight on into the next issue.
  def handle_event("next_page", _params, %{assigns: %{at_end: true, next_href: href}} = socket) do
    if href, do: {:noreply, push_navigate(socket, to: href, replace: true)}, else: {:noreply, socket}
  end

  def handle_event("next_page", _params, socket) do
    if last_page_showing?(socket.assigns) do
      {:noreply, show_end(socket)}
    else
      step = next_step(socket.assigns.page_layout, socket.assigns.current_page)
      new_page = min(socket.assigns.current_page + step, socket.assigns.page_count - 1)
      {:noreply, socket |> assign(:current_page, new_page) |> schedule_progress_save()}
    end
  end

  def handle_event("goto_page", %{"page" => page_str}, socket) do
    page = String.to_integer(page_str)
    new_page = max(0, min(page, socket.assigns.page_count - 1))
    {:noreply, socket |> assign(current_page: new_page, at_end: false) |> schedule_progress_save()}
  end

  # Leaving is an event rather than a plain link so the pending save lands before
  # the next page loads and reads it. The client picks how to get there (see the
  # "reader:exit" handler in app.js) so the reader never stays in the history.
  def handle_event("exit", %{"to" => to}, socket) when to in ["book", "series"] do
    book = socket.assigns.book

    path =
      if to == "series" and book.series_id,
        do: ~p"/series/#{book.series_id}",
        else: ~p"/book/#{book.id}"

    {:noreply, socket |> flush_progress() |> push_event("reader:exit", %{to: path})}
  end

  def handle_event("set_layout", %{"layout" => layout}, socket)
      when layout in ["single", "double", "cover"] do
    socket = assign(socket, page_layout: layout, layout_menu_open: false)
    save_reader_settings(socket)
    {:noreply, socket}
  end

  def handle_event("toggle_layout_menu", _params, socket) do
    {:noreply, assign(socket, :layout_menu_open, !socket.assigns.layout_menu_open)}
  end

  def handle_event("close_layout_menu", _params, socket) do
    {:noreply, assign(socket, :layout_menu_open, false)}
  end

  def handle_event("toggle_overlay", _params, socket) do
    {:noreply, assign(socket, overlay_visible: !socket.assigns.overlay_visible, layout_menu_open: false)}
  end

  def handle_event("set_fit", %{"mode" => mode}, socket)
      when mode in ["page", "width", "height"] do
    socket = assign(socket, fit_mode: mode)
    save_reader_settings(socket)
    {:noreply, socket}
  end

  def handle_event("toggle_direction", _params, socket) do
    new_dir = if socket.assigns.direction == "ltr", do: "rtl", else: "ltr"
    socket = assign(socket, :direction, new_dir)
    save_reader_settings(socket)
    {:noreply, socket}
  end

  def handle_info({:scan_progress, _}, socket), do: {:noreply, socket}
  def handle_info({:book_added, _}, socket), do: {:noreply, socket}
  def handle_info({:cover_updated, _}, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:save_progress, socket) do
    {:noreply, save_progress(socket)}
  end

  defp save_progress(socket) do
    page = socket.assigns.current_page

    if page > 0 do
      Library.update_progress(socket.assigns.access, socket.assigns.current_user.id, socket.assigns.book.id, page)
    end

    assign(socket, :save_timer, nil)
  end

  # Writes a debounced save that is still pending; a no-op when nothing is waiting.
  defp flush_progress(%{assigns: %{save_timer: nil}} = socket), do: socket

  defp flush_progress(socket) do
    Process.cancel_timer(socket.assigns.save_timer)
    save_progress(socket)
  end

  # Read detection compares progress against book.page_count, so keep it equal to
  # what the reader can actually page through (stale scans, ComicInfo PageCount).
  defp sync_page_count(book, count) when count > 0 and book.page_count != count do
    case Library.update_book(book, %{page_count: count}) do
      {:ok, updated} -> updated
      _ -> book
    end
  end

  defp sync_page_count(book, _count), do: book

  defp spread?(%{page_layout: layout, current_page: page, page_count: count}),
    do: (layout == "double" or (layout == "cover" and page > 0)) and page + 1 < count

  defp last_page_showing?(%{page_count: count} = assigns) do
    last_visible = assigns.current_page + if(spread?(assigns), do: 1, else: 0)
    count > 0 and last_visible >= count - 1
  end

  # Reaching the end card means the book is finished: save that now rather than on
  # the debounce, so the pages its buttons lead to already show it as read.
  defp show_end(socket) do
    if socket.assigns.save_timer, do: Process.cancel_timer(socket.assigns.save_timer)
    %{access: access, current_user: user, book: book, page_count: count} = socket.assigns
    Library.update_progress(access, user.id, book.id, count - 1)
    assign(socket, at_end: true, save_timer: nil)
  end

  # A finished next issue would resume on its last page; start it over instead.
  defp next_href(user_id, next_book) do
    progress = Library.get_progress(user_id, next_book.id)
    finished = progress && next_book.page_count > 0 && progress.current_page >= next_book.page_count - 1
    if finished, do: ~p"/read/#{next_book.id}?page=0", else: ~p"/read/#{next_book.id}"
  end

  defp issue_label(%{issue_number: nil}), do: nil
  defp issue_label(%{issue_number: n}), do: "##{Decimal.to_integer(n)}"

  defp schedule_progress_save(socket) do
    if socket.assigns.save_timer, do: Process.cancel_timer(socket.assigns.save_timer)
    timer = Process.send_after(self(), :save_progress, @progress_debounce_ms)
    assign(socket, :save_timer, timer)
  end

  defp next_step("double", _page), do: 2
  defp next_step("cover", 0), do: 1
  defp next_step("cover", _page), do: 2
  defp next_step(_single, _page), do: 1

  defp prev_step("double", _page), do: 2
  defp prev_step("cover", 1), do: 1
  defp prev_step("cover", _page), do: 2
  defp prev_step(_single, _page), do: 1

  defp preload_offsets("double"), do: [2, 3, 4, -2]
  defp preload_offsets("cover"), do: [2, 3, 4, -2]
  defp preload_offsets(_single), do: [1, 2, -1]

  defp save_reader_settings(socket) do
    user = socket.assigns.current_user

    settings = %{
      "page_layout" => socket.assigns.page_layout,
      "direction" => socket.assigns.direction,
      "fit_mode" => socket.assigns.fit_mode
    }

    Accounts.save_reader_settings(user, settings)
  end

  defp img_fit_style("width"), do: "width: 100%; height: auto; max-height: none; max-width: none;"

  defp img_fit_style("height"),
    do: "height: 100%; width: auto; max-height: none; max-width: none;"

  defp img_fit_style(_page), do: "max-height: 100%; max-width: 100%; width: auto; height: auto;"

  defp fit_modes do
    [
      {"page", "Fit page", "lucide-scan"},
      {"width", "Fit width", "lucide-move-horizontal"},
      {"height", "Fit height", "lucide-move-vertical"}
    ]
  end

  defp layout_icon("double"), do: "lucide-columns-2"
  defp layout_icon("cover"), do: "lucide-layout-panel-top"
  defp layout_icon(_single), do: "lucide-rectangle-vertical"

  # One cell of a .ink-segmented.
  defp ctl_class(active) do
    [
      "flex items-center justify-center h-8 min-w-8 px-2 transition-colors",
      if(active, do: "bg-violet-600 text-white", else: "text-gray-300 hover:text-white hover:bg-white/10")
    ]
  end

  defp slider_fill(_page, count) when count <= 1, do: 100
  defp slider_fill(page, count), do: Float.round(page / (count - 1) * 100, 2)

  attr :event, :string, required: true
  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, required: true

  defp menu_option(assigns) do
    ~H"""
    <button
      phx-click={@event}
      {%{"phx-value-#{@name}" => @value}}
      class={[
        "ink-menu-item w-full flex items-center gap-3 px-2 py-2 rounded-sm text-sm text-left transition-colors",
        if(@active,
          do: "is-active bg-white/[0.07] text-white",
          else: "text-gray-300 hover:text-white hover:bg-white/[0.05]"
        )
      ]}
    >
      <.icon name={@icon} class={"w-4 h-4 flex-shrink-0 #{if @active, do: "text-ink", else: "text-gray-500"}"} />
      <span class="flex-1 font-display font-bold uppercase tracking-wide">{@label}</span>
      <.icon :if={@active} name="lucide-check" class="w-3.5 h-3.5 text-ink" />
    </button>
    """
  end

  attr :book, :map, required: true
  attr :next_book, :map, default: nil
  attr :next_href, :string, default: nil

  # The "ghost page" past the last one. It is pointer-events-none so the click
  # zones underneath keep working (left steps back, right carries on); only the
  # links take pointers, which ReaderZoom already leaves alone.
  defp end_card(assigns) do
    assigns =
      assign(assigns, label: issue_label(assigns.book), next_label: assigns.next_book && issue_label(assigns.next_book))

    ~H"""
    <div
      id="reader-end"
      class="reader-end absolute inset-0 z-20 pointer-events-none flex items-center justify-center px-6 py-16 overflow-hidden bg-zinc-950/85 backdrop-blur-md"
      role="region"
      aria-label="End of issue"
    >
      <div class="halftone absolute inset-0" aria-hidden="true"></div>
      <.ghost_numeral class="absolute -right-6 -bottom-12 text-[16rem] md:text-[26rem]">
        {if @next_book, do: String.trim_leading(@next_label || "", "#"), else: "END"}
      </.ghost_numeral>

      <div class="relative flex flex-col sm:flex-row items-center gap-7 sm:gap-12 max-w-3xl">
        <%!-- The page that isn't there: next cover, or a hollow one with a ghost in it --%>
        <%= if @next_book do %>
          <.link
            navigate={@next_href}
            replace
            class="reader-end-page pointer-events-auto relative block w-28 sm:w-48 flex-shrink-0 aspect-[2/3] rounded-sm bg-zinc-900"
            aria-label={"Read next issue #{@next_label}"}
          >
            <img
              src={~p"/api/books/#{@next_book.id}/cover?s=m"}
              alt=""
              class="w-full h-full object-cover rounded-sm"
              onerror="this.style.display='none'"
              draggable="false"
            />
            <.sticker size="md" tilt={false} class="reader-end-sticker absolute -top-3 -left-4">
              Next {@next_label}
            </.sticker>
          </.link>
        <% else %>
          <div class="reader-end-page reader-end-hollow relative flex items-center justify-center w-28 sm:w-48 flex-shrink-0 aspect-[2/3] rounded-sm">
            <.icon name="lucide-ghost" class="reader-end-ghost w-12 h-12 sm:w-20 sm:h-20 text-ink" />
          </div>
        <% end %>

        <div class="min-w-0 text-center sm:text-left">
          <.eyebrow class="rise" style="--i:1">
            End of {if @label, do: "issue #{@label}", else: "the book"}
            <span class="reader-end-stamp ml-2 inline-flex items-center gap-1 px-1.5 py-px border-2 border-ink text-ink rounded-sm">
              <.icon name="lucide-check" class="w-3 h-3" /> Read
            </span>
          </.eyebrow>

          <.display_heading size="hero" class="rise mt-3" style="--i:2">
            {if @next_book, do: "To be continued", else: "The End"}
          </.display_heading>

          <%!-- Narration box, as lettered in the gutter of a last panel --%>
          <p
            class="rise reader-end-caption inline-block mt-5 px-3 py-1.5 bg-ink text-zinc-950 text-sm font-semibold"
            style="--i:3"
          >
            <%= cond do %>
              <% @next_book -> %>
                Meanwhile, in issue {@next_label}…
              <% @book.series -> %>
                That was the last one. Nothing past here but ghosts.
              <% true -> %>
                And they all closed the book. Nothing past here but ghosts.
            <% end %>
          </p>

          <div class="rise flex flex-wrap items-center justify-center sm:justify-start gap-x-4 gap-y-4 mt-7" style="--i:4">
            <.ink_button :if={@next_book} navigate={@next_href} replace class="pointer-events-auto">
              Next issue <span class="text-ink">{@next_label}</span>
              <.icon name="lucide-arrow-right" class="w-4 h-4" />
            </.ink_button>
            <.ink_button variant="ghost" phx-click="exit" phx-value-to="book" class="reader-end-alt pointer-events-auto">
              <.icon name="lucide-book-open" class="w-4 h-4" /> Issue page
            </.ink_button>
            <.ink_button
              :if={@book.series}
              variant={if @next_book, do: "ghost", else: "primary"}
              phx-click="exit"
              phx-value-to="series"
              class={["pointer-events-auto", if(@next_book, do: "reader-end-alt", else: "order-first")]}
            >
              <.icon name="lucide-library" class="w-4 h-4" /> Back to series
            </.ink_button>
          </div>

          <p
            class="rise hidden sm:flex items-center gap-2 mt-6 text-[11px] tracking-[0.16em] uppercase text-gray-500"
            style="--i:5"
          >
            <span :if={@next_book}><kbd class="text-gray-300">→</kbd> keep reading</span>
            <span :if={@next_book} class="text-white/25">/</span>
            <span><kbd class="text-gray-300">←</kbd> last page</span>
          </p>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- No <html>/<head>/<body> here: the :browser pipeline already wraps
         every LiveView in the root layout, which supplies the document, the
         csrf token and app.js. Emitting a second full document nested inside
         it made the browser hoist a duplicate <script src="app.js">, which
         booted a second LiveSocket ("Cannot bind multiple views to the same
         DOM element") and mounted every hook twice. Two ReaderZoom instances
         on one element is what kept snapping the zoom back to 1. --%>
    <style>
      html, body { margin: 0; padding: 0; height: 100%; overflow: hidden; }
      .reader-page { cursor: pointer; user-select: none; }
      /* Own the touch gestures: without this the browser runs its native
         pinch-zoom on the same fingers and the page jitters. Must be CSS,
         not an inline style -- LiveView's DOM patch strips those. */
      #reading-area { touch-action: none; }
      .reader-zone-left { cursor: w-resize; }
      .reader-zone-right { cursor: e-resize; }
    </style>
    <div
      class="relative bg-black"
      style="height: 100dvh;"
      id="reader-container"
      phx-hook="ReaderKeyboard"
    >
      <%!-- Top bar overlay --%>
      <div
        class={[
          "reader-bar reader-bar-top absolute top-0 left-0 right-0 z-30 flex items-center gap-3 px-3 sm:px-4 transition-transform duration-200",
          if(@overlay_visible, do: "translate-y-0", else: "-translate-y-full")
        ]}
        style="height: 48px;"
      >
        <%!-- Left: close, always to the book page --%>
        <button
          phx-click="exit"
          phx-value-to="book"
          title="Close reader"
          class="group flex items-center gap-1.5 h-8 pl-1.5 pr-2.5 rounded-md text-gray-400 hover:text-white hover:bg-white/10 font-display font-bold uppercase tracking-wide transition-colors whitespace-nowrap"
        >
          <.icon name="lucide-x" class="w-4 h-4 transition-transform group-hover:rotate-90" />
          <span class="hidden sm:inline">Close</span>
        </button>

        <%!-- Center: issue sticker + series (or book) title --%>
        <div class="flex-1 min-w-0 flex items-center justify-center gap-2.5">
          <.sticker :if={lbl = issue_label(@book)} class="flex-shrink-0">{lbl}</.sticker>
          <span class="truncate font-display font-extrabold uppercase tracking-wide text-lg leading-none text-white">
            {(@book.series && @book.series.name) || @book.title}
          </span>
        </div>

        <%!-- Right: controls + page counter --%>
        <div class="flex items-center gap-2 flex-shrink-0">
          <%!-- View menu: layout, plus fit and direction on small screens --%>
          <div class="relative">
            <div class="ink-segmented">
              <button
                phx-click="toggle_layout_menu"
                title="View options"
                aria-expanded={to_string(@layout_menu_open)}
                class={[ctl_class(@layout_menu_open), "gap-1.5 px-2.5"]}
              >
                <.icon name={layout_icon(@page_layout)} class="w-4 h-4 flex-shrink-0" />
                <span class="hidden md:inline font-display font-bold uppercase tracking-wide text-sm">View</span>
                <.icon
                  name="lucide-chevron-down"
                  class={"w-3 h-3 flex-shrink-0 transition-transform#{if @layout_menu_open, do: " rotate-180", else: ""}"}
                />
              </button>
            </div>

            <%= if @layout_menu_open do %>
              <div class="fixed inset-0 z-20" phx-click="close_layout_menu" />
              <div class="ink-menu absolute right-0 top-full mt-2 z-30 w-60 p-1.5 rounded-md bg-zinc-950 ring-1 ring-white/15 shadow-2xl">
                <p class="ink-menu-label">Layout</p>
                <.menu_option
                  :for={
                    {layout, label} <- [
                      {"single", "Single page"},
                      {"double", "Facing pages"},
                      {"cover", "Facing, cover first"}
                    ]
                  }
                  event="set_layout"
                  name="layout"
                  value={layout}
                  icon={layout_icon(layout)}
                  label={label}
                  active={@page_layout == layout}
                />

                <div class="sm:hidden">
                  <p class="ink-menu-label mt-2">Fit</p>
                  <.menu_option
                    :for={{mode, label, icon} <- fit_modes()}
                    event="set_fit"
                    name="mode"
                    value={mode}
                    icon={icon}
                    label={label}
                    active={@fit_mode == mode}
                  />

                  <p class="ink-menu-label mt-2">Direction</p>
                  <.menu_option
                    event="toggle_direction"
                    name="dir"
                    value={@direction}
                    icon={if @direction == "ltr", do: "lucide-arrow-right", else: "lucide-arrow-left"}
                    label={if @direction == "ltr", do: "Left to right", else: "Right to left"}
                    active={false}
                  />
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Fit mode --%>
          <div class="ink-segmented hidden sm:flex divide-x divide-white/10">
            <button
              :for={{mode, label, icon} <- fit_modes()}
              phx-click="set_fit"
              phx-value-mode={mode}
              title={label}
              aria-pressed={to_string(@fit_mode == mode)}
              class={ctl_class(@fit_mode == mode)}
            >
              <.icon name={icon} class="w-4 h-4" />
            </button>
          </div>

          <%!-- Direction toggle --%>
          <div class="ink-segmented hidden sm:flex">
            <button
              phx-click="toggle_direction"
              title="Toggle reading direction (LTR/RTL)"
              class={[ctl_class(false), "gap-1 px-2.5 font-display font-bold tracking-wide text-sm"]}
            >
              {@direction |> String.upcase()}
              <.icon
                name={if @direction == "ltr", do: "lucide-arrow-right", else: "lucide-arrow-left"}
                class="w-3.5 h-3.5 text-ink"
              />
            </button>
          </div>

          <%!-- Page counter --%>
          <p class="min-w-[3.25rem] text-right tabular-nums leading-none whitespace-nowrap">
            <%= if @at_end do %>
              <span class="font-display font-black uppercase tracking-wide text-xl text-ink">End</span>
            <% else %>
              <span class="font-display font-black text-xl text-white">{@current_page + 1}</span>
              <span class="text-gray-600 text-xs"> / {@page_count}</span>
            <% end %>
          </p>
        </div>
      </div>

      <%!-- Reading area (full viewport) --%>
      <div
        class="absolute inset-0 overflow-hidden select-none"
        id="reading-area"
        phx-hook="ReaderZoom"
      >
        <%!-- Click zones. These carry data-action, not phx-click: the
             ReaderZoom hook owns every pointer interaction in the reading
             area (tap to navigate, double tap to zoom, drag to pan, pinch)
             and pushes the event itself once it knows which gesture it
             was. Side-zone taps fire immediately; only the centre zone
             waits, since that is where double tap to zoom lives. --%>
        <%!-- Click zone: left (prev in LTR, next in RTL) --%>
        <div
          class="absolute left-0 top-0 bottom-0 z-10 reader-zone-left reader-click-zone"
          style="width: 22%;"
          data-action={if @direction == "ltr", do: "prev_page", else: "next_page"}
        />

        <%!-- Click zone: center (toggle overlay) --%>
        <div
          class="absolute top-0 bottom-0 z-10 reader-zone-center reader-click-zone"
          style="left: 22%; width: 56%; cursor: default;"
          data-action="toggle_overlay"
        />

        <%!-- Click zone: right (next in LTR, prev in RTL) --%>
        <div
          class="absolute right-0 top-0 bottom-0 z-10 reader-zone-right reader-click-zone"
          style="width: 22%;"
          data-action={if @direction == "ltr", do: "next_page", else: "prev_page"}
        />

        <%!-- Floating zoom controls --%>
        <div
          class={[
            "absolute transition-transform duration-200",
            if(@overlay_visible, do: "translate-x-0", else: "translate-x-[calc(100%+16px)]")
          ]}
          style="top: 64px; right: 16px; z-index: 25;"
        >
          <div class="ink-segmented reader-ctl-float flex-col divide-y divide-white/10">
            <button
              onclick="window.dispatchEvent(new CustomEvent('reader:zoom-in'))"
              title="Zoom in (+)"
              class={ctl_class(false)}
            >
              <.icon name="lucide-plus" class="w-4 h-4" />
            </button>
            <button
              onclick="window.dispatchEvent(new CustomEvent('reader:zoom-out'))"
              title="Zoom out (-)"
              class={ctl_class(false)}
            >
              <.icon name="lucide-minus" class="w-4 h-4" />
            </button>
            <%!-- Zoom readout, filled in and shown by ReaderZoom while zoomed --%>
            <button
              id="reader-zoom-level"
              phx-update="ignore"
              onclick="window.dispatchEvent(new CustomEvent('reader:zoom-reset'))"
              title="Reset zoom (0)"
              class="items-center justify-center h-7 min-w-8 px-1 font-display font-bold text-xs text-ink tabular-nums hover:bg-white/10 transition-colors"
              style="display: none;"
            ></button>
          </div>
        </div>

        <%!-- Pages --%>
        <div
          id="reader-pages"
          class={[
            "flex items-center justify-center h-full",
            if(@direction == "rtl", do: "flex-row-reverse", else: "flex-row")
          ]}
          style="transform-origin: center; will-change: transform;"
        >
          <div
            class="relative flex items-center justify-center h-full"
            style={
              if @page_layout in ["double"] || (@page_layout == "cover" && @current_page > 0),
                do: "max-width: 50%",
                else: "max-width: 100%"
            }
          >
            <div
              class="absolute inset-0 flex items-center justify-center pointer-events-none"
              style="display: flex;"
            >
              <.icon name="lucide-loader-circle" class="animate-spin h-8 w-8 text-ink/50" />
            </div>
            <img
              id="reader-page-main"
              phx-hook="PageImage"
              src={
                "/api/books/#{@book.id}/page/#{@current_page}#{if @book_format, do: "?format=#{@book_format}", else: ""}"
              }
              alt={"Page #{@current_page + 1}"}
              class="object-contain"
              style={"#{img_fit_style(@fit_mode)} opacity: 0; transition: opacity 0.15s ease;"}
              draggable="false"
            />
          </div>
          <%= if spread?(assigns) do %>
            <div class="relative flex items-center justify-center h-full" style="max-width: 50%">
              <div
                class="absolute inset-0 flex items-center justify-center pointer-events-none"
                style="display: flex;"
              >
                <.icon name="lucide-loader-circle" class="animate-spin h-8 w-8 text-ink/50" />
              </div>
              <img
                id="reader-page-second"
                phx-hook="PageImage"
                src={
                  "/api/books/#{@book.id}/page/#{@current_page + 1}#{if @book_format, do: "?format=#{@book_format}", else: ""}"
                }
                alt={"Page #{@current_page + 2}"}
                class="object-contain"
                style={"#{img_fit_style(@fit_mode)} opacity: 0; transition: opacity 0.15s ease;"}
                draggable="false"
              />
            </div>
          <% end %>
        </div>

        <.end_card :if={@at_end} book={@book} next_book={@next_book} next_href={@next_href} />

        <%!-- Preload adjacent pages --%>
        <div class="hidden" aria-hidden="true">
          <%= for offset <- preload_offsets(@page_layout) do %>
            <% p = @current_page + offset %>
            <%= if p >= 0 && p < @page_count do %>
              <img src={"/api/books/#{@book.id}/page/#{p}#{if @book_format, do: "?format=#{@book_format}", else: ""}"} />
            <% end %>
          <% end %>
        </div>

        <%!-- Bottom bar: scrubber --%>
        <div class={[
          "reader-bar reader-bar-bottom absolute bottom-0 left-0 right-0 z-30 px-4 py-2.5 transition-transform duration-200",
          if(@overlay_visible, do: "translate-y-0", else: "translate-y-full")
        ]}>
          <div class="flex items-center gap-4">
            <span class="w-8 text-right font-display font-black text-xl leading-none text-white tabular-nums">
              {@current_page + 1}
            </span>
            <input
              id="page-slider"
              type="range"
              min="0"
              max={@page_count - 1}
              value={@current_page}
              phx-hook="PageSlider"
              aria-label="Page"
              class="reader-slider flex-1"
              style={"--fill: #{slider_fill(@current_page, @page_count)}%"}
            />
            <span class="w-8 font-display font-bold text-base leading-none text-gray-500 tabular-nums">
              {@page_count}
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
