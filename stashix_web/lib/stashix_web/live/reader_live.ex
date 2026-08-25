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
       layout: "single",
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

  def handle_event("toggle_layout", _params, socket) do
    new_layout = if socket.assigns.layout == "single", do: "double", else: "single"
    {:noreply, assign(socket, :layout, new_layout)}
  end

  @impl true
  def handle_info(:save_progress, socket) do
    user_id = socket.assigns.current_user.id
    book_id = socket.assigns.book.id
    page = socket.assigns.current_page
    Library.update_progress(user_id, book_id, page)
    {:noreply, assign(socket, :save_timer, nil)}
  end

  defp schedule_progress_save(socket) do
    if socket.assigns.save_timer do
      Process.cancel_timer(socket.assigns.save_timer)
    end

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
      </head>
      <body class="bg-black">
        <div
          class="min-h-screen flex flex-col"
          phx-window-keydown="keydown"
          phx-key=""
          id="reader-container"
          phx-hook="ReaderKeyboard"
        >
          <div class="flex items-center justify-between px-4 py-2 bg-gray-950 border-b border-gray-800">
            <a href={~p"/book/#{@book.id}"} class="text-gray-400 hover:text-white text-sm">
              ← {@book.title}
            </a>

            <div class="flex items-center gap-4 text-sm text-gray-400">
              <span>{@current_page + 1} / {@page_count}</span>

              <button
                phx-click="toggle_layout"
                class="px-2 py-1 bg-gray-800 hover:bg-gray-700 rounded text-xs"
              >
                {if @layout == "single", do: "Single", else: "Double"}
              </button>
            </div>
          </div>

          <div class="flex-1 flex items-center justify-center relative select-none">
            <button
              phx-click="prev_page"
              disabled={@current_page == 0}
              class="absolute left-2 z-10 p-3 bg-black/50 hover:bg-black/80 text-white rounded-full disabled:opacity-20 transition-all"
            >
              ‹
            </button>

            <div class={[
              "flex items-center justify-center gap-1 h-full max-h-screen p-4",
              if(@layout == "double", do: "max-w-6xl", else: "max-w-3xl")
            ]}>
              <img
                src={~p"/api/books/#{@book.id}/page/#{@current_page}"}
                alt={"Page #{@current_page + 1}"}
                class="max-h-full max-w-full object-contain"
              />
              <%= if @layout == "double" && @current_page + 1 < @page_count do %>
                <img
                  src={~p"/api/books/#{@book.id}/page/#{@current_page + 1}"}
                  alt={"Page #{@current_page + 2}"}
                  class="max-h-full max-w-full object-contain"
                />
              <% end %>
            </div>

            <button
              phx-click="next_page"
              disabled={@current_page >= @page_count - 1}
              class="absolute right-2 z-10 p-3 bg-black/50 hover:bg-black/80 text-white rounded-full disabled:opacity-20 transition-all"
            >
              ›
            </button>
          </div>

          <div class="px-4 py-2 bg-gray-950 border-t border-gray-800">
            <input
              type="range"
              min="0"
              max={max(@page_count - 1, 0)}
              value={@current_page}
              phx-change="goto_page"
              name="page"
              class="w-full accent-indigo-500"
            />
          </div>
        </div>
      </body>
    </html>
    """
  end
end
