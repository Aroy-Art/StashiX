defmodule StashixWeb.ReaderLive do
  use StashixWeb, :live_view

  alias Stashix.{Accounts, Library, Media.Extractor}

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @progress_debounce_ms 2_000

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    book = Library.get_book!(id)

    pages =
      case Extractor.list_pages(book.path) do
        {:ok, p} -> p
        _ -> []
      end

    user = socket.assigns.current_user
    progress = Library.get_progress(user.id, id)
    current_page =
      case Map.get(params, "page") do
        "0" -> 0
        _ -> (progress && progress.current_page) || 0
      end

    settings = user.reader_settings || %{}
    page_layout = Map.get(settings, "page_layout", "single")
    direction = Map.get(settings, "direction", "ltr")
    fit_mode = Map.get(settings, "fit_mode", "page")

    {:ok,
     assign(socket,
       page_title: "Reading: #{book.title}",
       book: book,
       pages: pages,
       page_count: length(pages),
       current_page: current_page,
       page_layout: page_layout,
       direction: direction,
       fit_mode: fit_mode,
       layout_menu_open: false,
       overlay_visible: true,
       save_timer: nil
     ),
     layout: false}
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    step = prev_step(socket.assigns.page_layout, socket.assigns.current_page)
    new_page = max(socket.assigns.current_page - step, 0)
    {:noreply, socket |> assign(:current_page, new_page) |> schedule_progress_save()}
  end

  def handle_event("next_page", _params, socket) do
    step = next_step(socket.assigns.page_layout, socket.assigns.current_page)
    new_page = min(socket.assigns.current_page + step, socket.assigns.page_count - 1)
    {:noreply, socket |> assign(:current_page, new_page) |> schedule_progress_save()}
  end

  def handle_event("goto_page", %{"page" => page_str}, socket) do
    page = String.to_integer(page_str)
    new_page = max(0, min(page, socket.assigns.page_count - 1))
    {:noreply, socket |> assign(:current_page, new_page) |> schedule_progress_save()}
  end

  def handle_event("set_layout", %{"layout" => layout}, socket) when layout in ["single", "double", "cover"] do
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

  def handle_event("set_fit", %{"mode" => mode}, socket) when mode in ["page", "width", "height"] do
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

  @impl true
  def handle_info(:save_progress, socket) do
    page = socket.assigns.current_page
    if page > 0 do
      Library.update_progress(socket.assigns.current_user.id, socket.assigns.book.id, page)
    end
    {:noreply, assign(socket, :save_timer, nil)}
  end

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
  defp img_fit_style("height"), do: "height: 100%; width: auto; max-height: none; max-width: none;"
  defp img_fit_style(_page), do: "max-height: 100%; max-width: 100%; width: auto; height: auto;"

  @impl true
  def render(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>{@page_title} · Stashix</title>
        <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
        <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}>
        </script>
        <style>
          html, body { margin: 0; padding: 0; height: 100%; overflow: hidden; }
          .reader-page { cursor: pointer; user-select: none; }
          .reader-zone-left { cursor: w-resize; }
          .reader-zone-right { cursor: e-resize; }
          input[type=range]::-webkit-slider-thumb { appearance: none; width: 14px; height: 14px; border-radius: 50%; background: #8b5cf6; cursor: pointer; }
          input[type=range]::-moz-range-thumb { width: 14px; height: 14px; border-radius: 50%; background: #8b5cf6; cursor: pointer; border: none; }
        </style>
      </head>
      <body class="bg-black">
        <div
          class="relative"
          style="height: 100dvh;"
          id="reader-container"
          phx-hook="ReaderKeyboard"
        >
          <%!-- Top bar overlay --%>
          <div class={[
            "absolute top-0 left-0 right-0 z-30 flex items-center justify-between px-4 py-1 bg-zinc-950/95 backdrop-blur border-b border-zinc-800 transition-transform duration-200",
            if(@overlay_visible, do: "translate-y-0", else: "-translate-y-full")
          ]} style="height: 44px;">
            <%!-- Left: back --%>
            <div class="flex items-center min-w-0 w-36">
              <a
                href={~p"/book/#{@book.id}"}
                class="flex items-center gap-1.5 text-zinc-400 hover:text-white text-sm transition-colors whitespace-nowrap"
              >
                <.icon name="lucide-arrow-left" class="w-4 h-4" />
                Back
              </a>
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
                  <.icon name="lucide-columns-2" class="w-4 h-4 flex-shrink-0" />
                  View Mode
                  <.icon name="lucide-chevron-down" class={["w-3 h-3 flex-shrink-0 transition-transform", if(@layout_menu_open, do: "rotate-180", else: "")]} />
                </button>

                <%= if @layout_menu_open do %>
                  <div class="fixed inset-0 z-20" phx-click="close_layout_menu" />
                  <div class="absolute right-0 top-full mt-1 z-30 bg-zinc-900 border border-zinc-700 rounded-lg shadow-xl py-1 w-56">
                    <%!-- Single Page --%>
                    <button phx-click="set_layout" phx-value-layout="single" class="w-full flex items-center gap-3 px-3 py-2 text-sm hover:bg-zinc-800 transition-colors">
                      <span class={["w-3.5 h-3.5 rounded-full border-2 flex-shrink-0", if(@page_layout == "single", do: "border-violet-500 bg-violet-500", else: "border-zinc-600")]}></span>
                      <svg xmlns="http://www.w3.org/2000/svg" class={["w-4 h-4 flex-shrink-0", if(@page_layout == "single", do: "text-violet-400", else: "text-zinc-400")]} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75">
                        <rect x="5" y="3" width="14" height="18" rx="1"/>
                      </svg>
                      <span class={if(@page_layout == "single", do: "text-white font-medium", else: "text-zinc-300")}>Single Page</span>
                    </button>
                    <%!-- Facing Pages --%>
                    <button phx-click="set_layout" phx-value-layout="double" class="w-full flex items-center gap-3 px-3 py-2 text-sm hover:bg-zinc-800 transition-colors">
                      <span class={["w-3.5 h-3.5 rounded-full border-2 flex-shrink-0", if(@page_layout == "double", do: "border-violet-500 bg-violet-500", else: "border-zinc-600")]}></span>
                      <svg xmlns="http://www.w3.org/2000/svg" class={["w-4 h-4 flex-shrink-0", if(@page_layout == "double", do: "text-violet-400", else: "text-zinc-400")]} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75">
                        <rect x="2" y="3" width="9" height="18" rx="1"/>
                        <rect x="13" y="3" width="9" height="18" rx="1"/>
                      </svg>
                      <span class={if(@page_layout == "double", do: "text-white font-medium", else: "text-zinc-300")}>Facing Pages</span>
                    </button>
                    <%!-- Facing Pages Cover First --%>
                    <button phx-click="set_layout" phx-value-layout="cover" class="w-full flex items-center gap-3 px-3 py-2 text-sm hover:bg-zinc-800 transition-colors">
                      <span class={["w-3.5 h-3.5 rounded-full border-2 flex-shrink-0", if(@page_layout == "cover", do: "border-violet-500 bg-violet-500", else: "border-zinc-600")]}></span>
                      <svg xmlns="http://www.w3.org/2000/svg" class={["w-4 h-4 flex-shrink-0", if(@page_layout == "cover", do: "text-violet-400", else: "text-zinc-400")]} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75">
                        <rect x="8" y="2" width="8" height="10" rx="1"/>
                        <rect x="2" y="14" width="9" height="10" rx="1"/>
                        <rect x="13" y="14" width="9" height="10" rx="1"/>
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
                  class={["flex items-center px-2 py-1.5 rounded transition-colors", if(@fit_mode == "page", do: "bg-violet-600 text-white", else: "bg-zinc-800 text-zinc-300 hover:text-white hover:bg-zinc-700")]}
                >
                  <.icon name="lucide-maximize-2" class="w-4 h-4" />
                </button>
                <button
                  phx-click="set_fit"
                  phx-value-mode="width"
                  title="Fit width"
                  class={["flex items-center px-2 py-1.5 rounded transition-colors", if(@fit_mode == "width", do: "bg-violet-600 text-white", else: "bg-zinc-800 text-zinc-300 hover:text-white hover:bg-zinc-700")]}
                >
                  <.icon name="lucide-arrow-left-right" class="w-4 h-4" />
                </button>
                <button
                  phx-click="set_fit"
                  phx-value-mode="height"
                  title="Fit height"
                  class={["flex items-center px-2 py-1.5 rounded transition-colors", if(@fit_mode == "height", do: "bg-violet-600 text-white", else: "bg-zinc-800 text-zinc-300 hover:text-white hover:bg-zinc-700")]}
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
                {@current_page + 1} / {@page_count}
              </span>
            </div>
          </div>

          <%!-- Reading area (full viewport) --%>
          <div class="absolute inset-0 overflow-hidden select-none">
            <%!-- Click zone: left (prev in LTR, next in RTL) --%>
            <div
              class="absolute left-0 top-0 bottom-0 z-10 reader-zone-left"
              style="width: 30%;"
              phx-click={if @direction == "ltr", do: "prev_page", else: "next_page"}
            />

            <%!-- Click zone: center (toggle overlay) --%>
            <div
              class="absolute top-0 bottom-0 z-10"
              style="left: 30%; width: 40%; cursor: default;"
              phx-click="toggle_overlay"
            />

            <%!-- Click zone: right (next in LTR, prev in RTL) --%>
            <div
              class="absolute right-0 top-0 bottom-0 z-10 reader-zone-right"
              style="width: 30%;"
              phx-click={if @direction == "ltr", do: "next_page", else: "prev_page"}
            />

            <%!-- Pages --%>
            <div class={[
              "flex items-center justify-center h-full",
              if(@direction == "rtl", do: "flex-row-reverse", else: "flex-row")
            ]}>
              <div class="relative flex items-center justify-center h-full" style={if @page_layout in ["double"] || (@page_layout == "cover" && @current_page > 0), do: "max-width: 50%", else: "max-width: 100%"}>
                <div class="absolute inset-0 flex items-center justify-center pointer-events-none" style="display: flex;">
                  <.icon name="lucide-loader-circle" class="animate-spin h-8 w-8 text-zinc-600" />
                </div>
                <img
                  id="reader-page-main"
                  phx-hook="PageImage"
                  src={~p"/api/books/#{@book.id}/page/#{@current_page}"}
                  alt={"Page #{@current_page + 1}"}
                  class="object-contain"
                  style={"#{img_fit_style(@fit_mode)} opacity: 0; transition: opacity 0.15s ease;"}
                  draggable="false"
                />
              </div>
              <%= if (@page_layout == "double" || (@page_layout == "cover" && @current_page > 0)) && @current_page + 1 < @page_count do %>
                <div class="relative flex items-center justify-center h-full" style="max-width: 50%">
                  <div class="absolute inset-0 flex items-center justify-center pointer-events-none" style="display: flex;">
                    <svg class="animate-spin h-8 w-8 text-zinc-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
                      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/>
                    </svg>
                  </div>
                  <img
                    id="reader-page-second"
                    phx-hook="PageImage"
                    src={~p"/api/books/#{@book.id}/page/#{@current_page + 1}"}
                    alt={"Page #{@current_page + 2}"}
                    class="object-contain"
                    style={"#{img_fit_style(@fit_mode)} opacity: 0; transition: opacity 0.15s ease;"}
                    draggable="false"
                  />
                </div>
              <% end %>
            </div>

            <%!-- Preload adjacent pages --%>
            <div class="hidden" aria-hidden="true">
              <%= for offset <- preload_offsets(@page_layout) do %>
                <% p = @current_page + offset %>
                <%= if p >= 0 && p < @page_count do %>
                  <img src={~p"/api/books/#{@book.id}/page/#{p}"} />
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
      </body>
    </html>
    """
  end
end
