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
    if href, do: {:noreply, push_navigate(socket, to: href)}, else: {:noreply, socket}
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

  # Closing is an event rather than a plain link so the pending save lands before
  # the book page loads and reads it. `replace` keeps the reader out of history.
  def handle_event("close", _params, socket) do
    socket = flush_progress(socket)
    {:noreply, push_navigate(socket, to: ~p"/book/#{socket.assigns.book.id}", replace: true)}
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
      <span
        class="ghost-numeral absolute -right-6 -bottom-12 text-[16rem] md:text-[26rem]"
        aria-hidden="true"
      >
        {if @next_book, do: String.trim_leading(@next_label || "", "#"), else: "END"}
      </span>

      <div class="relative flex flex-col sm:flex-row items-center gap-7 sm:gap-12 max-w-3xl">
        <%!-- The page that isn't there: next cover, or a hollow one with a ghost in it --%>
        <%= if @next_book do %>
          <.link
            navigate={@next_href}
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
            <span class="reader-end-sticker absolute -top-3 -left-4 px-2.5 py-0.5 bg-ink text-zinc-950 font-display font-black uppercase text-lg leading-tight rounded-sm">
              Next {@next_label}
            </span>
          </.link>
        <% else %>
          <div class="reader-end-page reader-end-hollow relative flex items-center justify-center w-28 sm:w-48 flex-shrink-0 aspect-[2/3] rounded-sm">
            <.icon name="lucide-ghost" class="reader-end-ghost w-12 h-12 sm:w-20 sm:h-20 text-ink" />
          </div>
        <% end %>

        <div class="min-w-0 text-center sm:text-left">
          <p class="rise text-[11px] font-bold tracking-[0.2em] uppercase text-violet-300" style="--i:1">
            End of {if @label, do: "issue #{@label}", else: "the book"}
            <span class="reader-end-stamp ml-2 inline-flex items-center gap-1 px-1.5 py-px border-2 border-ink text-ink rounded-sm">
              <.icon name="lucide-check" class="w-3 h-3" /> Read
            </span>
          </p>

          <h2
            class="rise mt-3 font-display font-black uppercase text-5xl md:text-7xl leading-[0.88] text-white text-balance"
            style="--i:2"
          >
            {if @next_book, do: "To be continued", else: "The End"}
          </h2>

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
            <.link
              :if={@next_book}
              navigate={@next_href}
              class="ink-btn pointer-events-auto inline-flex items-center gap-2.5 px-6 py-2.5 bg-violet-600 hover:bg-violet-500 text-white font-display font-extrabold uppercase text-xl tracking-wide rounded-md"
            >
              Next issue <span class="text-ink">{@next_label}</span>
              <.icon name="lucide-arrow-right" class="w-4 h-4" />
            </.link>
            <.link
              navigate={~p"/book/#{@book.id}"}
              class="reader-end-alt pointer-events-auto inline-flex items-center gap-2 px-4 py-2.5 rounded-md ring-1 ring-white/15 bg-white/[0.04] hover:bg-white/[0.1] hover:ring-white/30 text-gray-200 hover:text-white font-display font-bold uppercase tracking-wide transition-colors"
            >
              <.icon name="lucide-book-open" class="w-4 h-4" /> Issue page
            </.link>
            <.link
              :if={@book.series}
              navigate={~p"/series/#{@book.series.id}"}
              class={[
                "pointer-events-auto inline-flex items-center gap-2 rounded-md font-display uppercase tracking-wide",
                if(@next_book,
                  do:
                    "reader-end-alt px-4 py-2.5 ring-1 ring-white/15 bg-white/[0.04] hover:bg-white/[0.1] hover:ring-white/30 text-gray-200 hover:text-white font-bold transition-colors",
                  else:
                    "ink-btn order-first px-6 py-2.5 bg-violet-600 hover:bg-violet-500 text-white font-extrabold text-xl"
                )
              ]}
            >
              <.icon name="lucide-library" class="w-4 h-4" /> Back to series
            </.link>
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
      input[type=range]::-webkit-slider-thumb { appearance: none; width: 14px; height: 14px; border-radius: 50%; background: #8b5cf6; cursor: pointer; }
      input[type=range]::-moz-range-thumb { width: 14px; height: 14px; border-radius: 50%; background: #8b5cf6; cursor: pointer; border: none; }
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
          "absolute top-0 left-0 right-0 z-30 flex items-center justify-between px-4 py-1 bg-zinc-950/95 backdrop-blur border-b border-zinc-800 transition-transform duration-200",
          if(@overlay_visible, do: "translate-y-0", else: "-translate-y-full")
        ]}
        style="height: 44px;"
      >
        <%!-- Left: close, always to the book page --%>
        <div class="flex items-center min-w-0 w-36">
          <button
            phx-click="close"
            class="flex items-center gap-1.5 text-zinc-400 hover:text-white text-sm transition-colors whitespace-nowrap"
          >
            <.icon name="lucide-x" class="w-4 h-4" /> Close
          </button>
        </div>

        <%!-- Center: title --%>
        <div class="flex-1 text-center px-4 min-w-0">
          <span class="text-white text-sm font-medium truncate block">{@book.title}</span>
        </div>

        <%!-- Right: controls + page counter --%>
        <div class="flex items-center gap-2 min-w-0 justify-end">
          <%!-- View mode dropdown --%>
          <div class="relative">
            <button
              phx-click="toggle_layout_menu"
              class="flex items-center gap-1.5 px-2.5 py-1.5 rounded text-xs text-zinc-300 hover:text-white bg-zinc-800 hover:bg-zinc-700 transition-colors whitespace-nowrap"
            >
              <.icon name="lucide-columns-2" class="w-4 h-4 flex-shrink-0" /> View Mode
              <.icon
                name="lucide-chevron-down"
                class={"w-3 h-3 flex-shrink-0 transition-transform#{if @layout_menu_open, do: " rotate-180", else: ""}"}
              />
            </button>

            <%= if @layout_menu_open do %>
              <div class="fixed inset-0 z-20" phx-click="close_layout_menu" />
              <div class="absolute right-0 top-full mt-1 z-30 bg-zinc-900 border border-zinc-700 rounded-lg shadow-xl py-1 w-56">
                <%!-- Single Page --%>
                <button
                  phx-click="set_layout"
                  phx-value-layout="single"
                  class="w-full flex items-center gap-3 px-3 py-2 text-sm hover:bg-zinc-800 transition-colors"
                >
                  <span class={[
                    "w-3.5 h-3.5 rounded-full border-2 flex-shrink-0",
                    if(@page_layout == "single",
                      do: "border-violet-500 bg-violet-500",
                      else: "border-zinc-600"
                    )
                  ]}></span>
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class={[
                      "w-4 h-4 flex-shrink-0",
                      if(@page_layout == "single", do: "text-violet-400", else: "text-zinc-400")
                    ]}
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.75"
                  >
                    <rect x="5" y="3" width="14" height="18" rx="1" />
                  </svg>
                  <span class={if(@page_layout == "single", do: "text-white font-medium", else: "text-zinc-300")}>Single Page</span>
                </button>
                <%!-- Facing Pages --%>
                <button
                  phx-click="set_layout"
                  phx-value-layout="double"
                  class="w-full flex items-center gap-3 px-3 py-2 text-sm hover:bg-zinc-800 transition-colors"
                >
                  <span class={[
                    "w-3.5 h-3.5 rounded-full border-2 flex-shrink-0",
                    if(@page_layout == "double",
                      do: "border-violet-500 bg-violet-500",
                      else: "border-zinc-600"
                    )
                  ]}></span>
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class={[
                      "w-4 h-4 flex-shrink-0",
                      if(@page_layout == "double", do: "text-violet-400", else: "text-zinc-400")
                    ]}
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.75"
                  >
                    <rect x="2" y="3" width="9" height="18" rx="1" />
                    <rect x="13" y="3" width="9" height="18" rx="1" />
                  </svg>
                  <span class={if(@page_layout == "double", do: "text-white font-medium", else: "text-zinc-300")}>Facing Pages</span>
                </button>
                <%!-- Facing Pages Cover First --%>
                <button
                  phx-click="set_layout"
                  phx-value-layout="cover"
                  class="w-full flex items-center gap-3 px-3 py-2 text-sm hover:bg-zinc-800 transition-colors"
                >
                  <span class={[
                    "w-3.5 h-3.5 rounded-full border-2 flex-shrink-0",
                    if(@page_layout == "cover",
                      do: "border-violet-500 bg-violet-500",
                      else: "border-zinc-600"
                    )
                  ]}></span>
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class={[
                      "w-4 h-4 flex-shrink-0",
                      if(@page_layout == "cover", do: "text-violet-400", else: "text-zinc-400")
                    ]}
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.75"
                  >
                    <rect x="8" y="2" width="8" height="10" rx="1" />
                    <rect x="2" y="14" width="9" height="10" rx="1" />
                    <rect x="13" y="14" width="9" height="10" rx="1" />
                  </svg>
                  <span class={if(@page_layout == "cover", do: "text-white font-medium", else: "text-zinc-300")}>Facing Pages (Cover First)</span>
                </button>
              </div>
            <% end %>
          </div>

          <%!-- Fit mode buttons --%>
          <div class="flex items-center gap-1">
            <button
              phx-click="set_fit"
              phx-value-mode="page"
              title="Fit page"
              class={[
                "flex items-center px-2 py-1.5 rounded transition-colors",
                if(@fit_mode == "page",
                  do: "bg-violet-600 text-white",
                  else: "bg-zinc-800 text-zinc-300 hover:text-white hover:bg-zinc-700"
                )
              ]}
            >
              <.icon name="lucide-maximize-2" class="w-4 h-4" />
            </button>
            <button
              phx-click="set_fit"
              phx-value-mode="width"
              title="Fit width"
              class={[
                "flex items-center px-2 py-1.5 rounded transition-colors",
                if(@fit_mode == "width",
                  do: "bg-violet-600 text-white",
                  else: "bg-zinc-800 text-zinc-300 hover:text-white hover:bg-zinc-700"
                )
              ]}
            >
              <.icon name="lucide-arrow-left-right" class="w-4 h-4" />
            </button>
            <button
              phx-click="set_fit"
              phx-value-mode="height"
              title="Fit height"
              class={[
                "flex items-center px-2 py-1.5 rounded transition-colors",
                if(@fit_mode == "height",
                  do: "bg-violet-600 text-white",
                  else: "bg-zinc-800 text-zinc-300 hover:text-white hover:bg-zinc-700"
                )
              ]}
            >
              <.icon name="lucide-arrow-up-down" class="w-4 h-4" />
            </button>
          </div>

          <%!-- Direction toggle --%>
          <button
            phx-click="toggle_direction"
            title="Toggle reading direction (LTR/RTL)"
            class="flex items-center px-2.5 py-1.5 rounded text-xs font-mono text-zinc-300 hover:text-white bg-zinc-800 hover:bg-zinc-700 transition-colors"
          >
            {@direction |> String.upcase()}
          </button>

          <%!-- Page counter --%>
          <span class="text-zinc-400 text-sm tabular-nums whitespace-nowrap">
            <%= if @at_end do %>
              <span class="font-display font-black uppercase tracking-wide text-ink">End</span>
            <% else %>
              {@current_page + 1} / {@page_count}
            <% end %>
          </span>
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

        <%!-- Floating zoom controls (Mapbox-style) --%>
        <div
          class={[
            "absolute transition-transform duration-200",
            if(@overlay_visible, do: "translate-x-0", else: "translate-x-[calc(100%+16px)]")
          ]}
          style="top: 56px; right: 16px; z-index: 25;"
        >
          <div class="flex flex-col rounded-md overflow-hidden shadow-xl border border-zinc-700 bg-zinc-900/90 backdrop-blur">
            <button
              onclick="window.dispatchEvent(new CustomEvent('reader:zoom-in'))"
              title="Zoom in (+)"
              class="flex items-center justify-center w-7 h-7 text-zinc-300 hover:text-white hover:bg-zinc-700 transition-colors border-b border-zinc-700"
            >
              <.icon name="lucide-plus" class="w-3.5 h-3.5" />
            </button>
            <button
              onclick="window.dispatchEvent(new CustomEvent('reader:zoom-out'))"
              title="Zoom out (-)"
              class="flex items-center justify-center w-7 h-7 text-zinc-300 hover:text-white hover:bg-zinc-700 transition-colors"
            >
              <.icon name="lucide-minus" class="w-3.5 h-3.5" />
            </button>
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
              <.icon name="lucide-loader-circle" class="animate-spin h-8 w-8 text-zinc-600" />
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
                <svg
                  class="animate-spin h-8 w-8 text-zinc-600"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <circle
                    class="opacity-25"
                    cx="12"
                    cy="12"
                    r="10"
                    stroke="currentColor"
                    stroke-width="4"
                  />
                  <path
                    class="opacity-75"
                    fill="currentColor"
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
                  />
                </svg>
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

        <%!-- Bottom progress bar overlay --%>
        <div class={[
          "absolute bottom-0 left-0 right-0 z-30 px-4 py-3 bg-zinc-950/95 backdrop-blur border-t border-zinc-800 transition-transform duration-200",
          if(@overlay_visible, do: "translate-y-0", else: "translate-y-full")
        ]}>
          <div class="flex items-center gap-3">
            <span class="text-zinc-400 text-xs tabular-nums whitespace-nowrap">{@current_page + 1}</span>
            <input
              id="page-slider"
              type="range"
              min="0"
              max={@page_count - 1}
              value={@current_page}
              phx-hook="PageSlider"
              class="flex-1 h-1.5 appearance-none bg-zinc-700 rounded-full accent-violet-500 cursor-pointer"
              style="outline: none;"
            />
            <span class="text-zinc-400 text-xs tabular-nums whitespace-nowrap">{@page_count}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
