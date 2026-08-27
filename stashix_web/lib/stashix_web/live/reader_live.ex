defmodule StashixWeb.ReaderLive do
  use StashixWeb, :live_view

  alias Stashix.{Library, Media.Extractor}

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @progress_debounce_ms 2_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    book = Library.get_book!(id)

    pages =
      case Extractor.list_pages(book.path) do
        {:ok, p} -> p
        _ -> []
      end

    progress = Library.get_progress(socket.assigns.current_user.id, id)
    current_page = (progress && progress.current_page) || 0

    {:ok,
     assign(socket,
       page_title: "Reading: #{book.title}",
       book: book,
       pages: pages,
       page_count: length(pages),
       current_page: current_page,
       page_layout: "single",
       direction: "ltr",
       save_timer: nil
     ),
     layout: false}
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    new_page = max(socket.assigns.current_page - 1, 0)
    {:noreply, socket |> assign(:current_page, new_page) |> schedule_progress_save()}
  end

  def handle_event("next_page", _params, socket) do
    new_page = min(socket.assigns.current_page + 1, socket.assigns.page_count - 1)
    {:noreply, socket |> assign(:current_page, new_page) |> schedule_progress_save()}
  end

  def handle_event("goto_page", %{"page" => page_str}, socket) do
    page = String.to_integer(page_str)
    new_page = max(0, min(page, socket.assigns.page_count - 1))
    {:noreply, socket |> assign(:current_page, new_page) |> schedule_progress_save()}
  end

  def handle_event("set_layout", %{"layout" => layout}, socket) when layout in ["single", "double"] do
    {:noreply, assign(socket, :page_layout, layout)}
  end

  def handle_event("toggle_direction", _params, socket) do
    new_dir = if socket.assigns.direction == "ltr", do: "rtl", else: "ltr"
    {:noreply, assign(socket, :direction, new_dir)}
  end

  def handle_info({:scan_progress, _}, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:save_progress, socket) do
    user_id = socket.assigns.current_user.id
    book_id = socket.assigns.book.id
    page = socket.assigns.current_page
    Library.update_progress(user_id, book_id, page)
    {:noreply, assign(socket, :save_timer, nil)}
  end

  defp schedule_progress_save(socket) do
    if socket.assigns.save_timer, do: Process.cancel_timer(socket.assigns.save_timer)
    timer = Process.send_after(self(), :save_progress, @progress_debounce_ms)
    assign(socket, :save_timer, timer)
  end

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
        </style>
      </head>
      <body class="bg-black">
        <div
          class="flex flex-col"
          style="height: 100dvh;"
          id="reader-container"
          phx-hook="ReaderKeyboard"
        >
          <%!-- Top bar --%>
          <div class="flex items-center justify-between px-4 py-2 bg-zinc-950 border-b border-zinc-800 shrink-0" style="height: 48px;">
            <%!-- Left: back --%>
            <div class="flex items-center min-w-0 w-36">
              <a
                href={~p"/book/#{@book.id}"}
                class="flex items-center gap-1.5 text-zinc-400 hover:text-white text-sm transition-colors whitespace-nowrap"
              >
                <svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M19 12H5M12 5l-7 7 7 7"/>
                </svg>
                Back
              </a>
            </div>

            <%!-- Center: title --%>
            <div class="flex-1 text-center px-4 min-w-0">
              <span class="text-white text-sm font-medium truncate block">{@book.title}</span>
            </div>

            <%!-- Right: controls + page counter --%>
            <div class="flex items-center gap-2 min-w-0 w-36 justify-end">
              <%!-- Single page layout --%>
              <button
                phx-click="set_layout"
                phx-value-layout="single"
                title="Single page"
                class={[
                  "p-1.5 rounded transition-colors",
                  if(@page_layout == "single",
                    do: "bg-zinc-600 text-white",
                    else: "text-zinc-400 hover:text-white hover:bg-zinc-800"
                  )
                ]}
              >
                <svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                  <rect x="5" y="3" width="14" height="18" rx="1"/>
                </svg>
              </button>

              <%!-- Double page layout --%>
              <button
                phx-click="set_layout"
                phx-value-layout="double"
                title="Double page spread"
                class={[
                  "p-1.5 rounded transition-colors",
                  if(@page_layout == "double",
                    do: "bg-zinc-600 text-white",
                    else: "text-zinc-400 hover:text-white hover:bg-zinc-800"
                  )
                ]}
              >
                <svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                  <rect x="2" y="3" width="9" height="18" rx="1"/>
                  <rect x="13" y="3" width="9" height="18" rx="1"/>
                </svg>
              </button>

              <%!-- Direction toggle --%>
              <button
                phx-click="toggle_direction"
                title="Toggle reading direction (LTR/RTL)"
                class="px-2 py-1 rounded text-xs font-mono text-zinc-400 hover:text-white hover:bg-zinc-800 transition-colors"
              >
                {@direction |> String.upcase()}
              </button>

              <%!-- Page counter --%>
              <span class="text-zinc-400 text-sm tabular-nums whitespace-nowrap">
                {@current_page + 1} / {@page_count}
              </span>
            </div>
          </div>

          <%!-- Reading area --%>
          <div class="flex-1 relative overflow-hidden select-none" style="min-height: 0;">
            <%!-- Click zone: left (prev in LTR, next in RTL) --%>
            <div
              class="absolute left-0 top-0 bottom-0 z-10 reader-zone-left"
              style="width: 30%;"
              phx-click={if @direction == "ltr", do: "prev_page", else: "next_page"}
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
              <div class="relative flex items-center justify-center h-full" style={if @page_layout == "double", do: "max-width: 50%", else: "max-width: 100%"}>
                <div class="absolute inset-0 flex items-center justify-center pointer-events-none" style="display: flex;">
                  <svg class="animate-spin h-8 w-8 text-zinc-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/>
                  </svg>
                </div>
                <img
                  id="reader-page-main"
                  phx-hook="PageImage"
                  src={~p"/api/books/#{@book.id}/page/#{@current_page}"}
                  alt={"Page #{@current_page + 1}"}
                  class="max-h-full max-w-full object-contain"
                  style="height: 100%; width: auto; opacity: 0; transition: opacity 0.15s ease;"
                  draggable="false"
                />
              </div>
              <%= if @page_layout == "double" && @current_page + 1 < @page_count do %>
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
                    class="max-h-full max-w-full object-contain"
                    style="height: 100%; width: auto; opacity: 0; transition: opacity 0.15s ease;"
                    draggable="false"
                  />
                </div>
              <% end %>
            </div>

            <%!-- Preload adjacent pages --%>
            <div class="hidden" aria-hidden="true">
              <%= if @current_page + 1 < @page_count do %>
                <img src={~p"/api/books/#{@book.id}/page/#{@current_page + 1}"} />
              <% end %>
              <%= if @current_page + 2 < @page_count do %>
                <img src={~p"/api/books/#{@book.id}/page/#{@current_page + 2}"} />
              <% end %>
              <%= if @current_page - 1 >= 0 do %>
                <img src={~p"/api/books/#{@book.id}/page/#{@current_page - 1}"} />
              <% end %>
            </div>
          </div>
        </div>
      </body>
    </html>
    """
  end
end
