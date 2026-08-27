defmodule StashixWeb.BookLive do
  use StashixWeb, :live_view

  alias Stashix.Library

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    book = Library.get_book_with_series(id)
    library = Library.get_library!(book.library_id)

    progress = Library.get_progress(socket.assigns.current_user.id, id)
    current_page = (progress && progress.current_page) || 0

    {:ok,
     assign(socket,
       page_title: book.title,
       book: book,
       library: library,
       progress: current_page,
       read_menu_open: false
     )}
  end

  @impl true
  def handle_event("toggle_read_menu", _params, socket) do
    {:noreply, assign(socket, read_menu_open: !socket.assigns.read_menu_open)}
  end

  def handle_event("close_read_menu", _params, socket) do
    {:noreply, assign(socket, read_menu_open: false)}
  end

  defp format_file_size(nil), do: "—"
  defp format_file_size(0), do: "—"

  defp format_file_size(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 1)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 1)} KB"
      true -> "#{bytes} B"
    end
  end

  defp format_age_rating(:unknown), do: "N/A"
  defp format_age_rating(:everyone), do: "Everyone"
  defp format_age_rating(:teen), do: "Teen"
  defp format_age_rating(:teen_plus), do: "Teen+"
  defp format_age_rating(:mature), do: "Mature"
  defp format_age_rating(:adult), do: "Adult"
  defp format_age_rating(:explicit), do: "Explicit"
  defp format_age_rating(_), do: "N/A"

  defp book_display_title(book) do
    cond do
      book.series && book.issue_number ->
        "#{book.series.name} ##{book.issue_number |> Decimal.to_integer()}"
      true ->
        book.title
    end
  end

  defp relative_path(book, library) do
    library.name <> "/" <> (String.replace_prefix(book.path, library.root_path, "") |> String.trim_leading("/"))
  end

  @impl true
  def handle_info({:scan_progress, _}, socket), do: {:noreply, socket}
  def handle_info({:book_added, _}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto space-y-6">
      <div class="flex items-center gap-2 text-sm">
        <button onclick="history.back()" class="text-gray-500 hover:text-gray-300 flex items-center gap-1">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
          </svg>
          Back
        </button>
        <span class="text-gray-700">/</span>
        <a href="/" class="text-gray-500 hover:text-gray-300">Home</a>
        <span class="text-gray-700">/</span>
        <a href={~p"/library/#{@library.id}"} class="text-gray-500 hover:text-gray-300">{@library.name}</a>
        <%= if @book.series do %>
          <span class="text-gray-700">/</span>
          <a href={~p"/series/#{@book.series.id}"} class="text-gray-500 hover:text-gray-300">{@book.series.name}</a>
        <% end %>
        <span class="text-gray-700">/</span>
        <span class="text-gray-300">{if @book.issue_number, do: "##{Decimal.to_integer(@book.issue_number)} – #{@book.title}", else: @book.title}</span>
      </div>

      <div class="flex gap-6 md:gap-8">
        <%!-- Cover --%>
        <div class="w-36 md:w-48 flex-shrink-0">
          <div class="aspect-[2/3] bg-gray-800/60 rounded-xl overflow-hidden">
            <%= if @book.cover do %>
              <img
                id={"book-cover-#{@book.id}"}
                phx-hook="CoverImage"
                src={~p"/api/books/#{@book.id}/cover?w=384"}
                alt={@book.title}
                class="w-full h-full object-cover"
              />
            <% else %>
              <div class="w-full h-full flex items-center justify-center text-gray-600">
                <.icon name="lucide-layers" class="w-10 h-10 md:w-14 md:h-14" />
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Info --%>
        <div class="flex-1 min-w-0">
          <%!-- Series link --%>
          <%= if @book.series do %>
            <div class="flex items-baseline gap-1.5">
              <a
                href={~p"/series/#{@book.series.id}"}
                class="text-violet-400 text-sm font-medium hover:text-violet-300 transition-colors"
              >
                {@book.series.name}
              </a>
              <%= if @book.series.start_year do %>
                <span class="text-gray-500 text-sm">
                  ({@book.series.start_year}{if @book.series.end_year, do: "–#{@book.series.end_year}", else: "–"})
                </span>
              <% end %>
            </div>
          <% end %>

          <%!-- Title --%>
          <h1 class="text-2xl md:text-3xl font-bold text-white mt-0.5">
            {book_display_title(@book)}
          </h1>

          <%!-- Issue subtitle --%>
          <%= if @book.issue_number do %>
            <p class="text-gray-400 text-sm mt-1">
              Issue #{Decimal.to_integer(@book.issue_number)}
            </p>
          <% end %>

          <%!-- Quick stats --%>
          <div class="flex items-center gap-5 mt-3 text-sm text-gray-400">
            <%= if @book.page_count > 0 do %>
              <span class="flex items-center gap-1.5">
                <.icon name="lucide-book-open" class="w-4 h-4" />
                {@book.page_count} pages
              </span>
            <% end %>
            <span class="flex items-center gap-1.5">
              <.icon name="lucide-file-text" class="w-4 h-4" />
              {String.upcase(to_string(@book.format))}
            </span>
          </div>

          <%!-- Progress bar --%>
          <%= if @progress > 0 && @book.page_count > 0 do %>
            <div class="mt-3">
              <div class="flex justify-between text-xs text-gray-500 mb-1">
                <span>Progress</span>
                <span>{@progress}/{@book.page_count} pages</span>
              </div>
              <div class="h-1 bg-gray-800 rounded-full overflow-hidden">
                <div
                  class="h-full bg-violet-500"
                  style={"width: #{round(@progress / @book.page_count * 100)}%"}
                >
                </div>
              </div>
            </div>
          <% end %>

          <%!-- Read button --%>
          <%= if @book.page_count > 0 do %>
            <div class="relative inline-flex mt-4">
              <a
                href={~p"/read/#{@book.id}"}
                class={[
                  "inline-flex items-center gap-2 px-5 py-2.5 bg-violet-600 hover:bg-violet-500 text-white text-sm font-medium transition-colors",
                  if(@progress > 0, do: "rounded-l-lg", else: "rounded-lg")
                ]}
              >
                <.icon name="lucide-book-open" class="w-4 h-4" />
                {if @progress > 0, do: "Continue", else: "Read"}
              </a>
              <%= if @progress > 0 do %>
                <button
                  phx-click="toggle_read_menu"
                  class="inline-flex items-center px-2 py-2.5 bg-violet-700 hover:bg-violet-600 text-white rounded-r-lg border-l border-violet-500 transition-colors"
                  aria-label="More reading options"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" class={["w-4 h-4 transition-transform", if(@read_menu_open, do: "rotate-180", else: "")]} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
                    <path d="M6 9l6 6 6-6"/>
                  </svg>
                </button>
                <%= if @read_menu_open do %>
                  <div class="fixed inset-0 z-20" phx-click="close_read_menu" />
                  <div class="absolute left-0 top-full mt-1 z-30 bg-zinc-900 border border-zinc-700 rounded-lg shadow-xl py-1 min-w-48">
                    <a
                      href={~p"/read/#{@book.id}?page=0"}
                      class="flex items-center gap-2 px-4 py-2 text-sm text-zinc-300 hover:text-white hover:bg-zinc-800 transition-colors"
                    >
                      <.icon name="lucide-rotate-ccw" class="w-4 h-4" />
                      Read from Beginning
                    </a>
                  </div>
                <% end %>
              <% end %>
            </div>
          <% end %>

          <%!-- Metadata grid --%>
          <div class="mt-6 grid grid-cols-2 md:grid-cols-3 gap-x-8 gap-y-4">
            <%= if @book.publisher do %>
              <div>
                <p class="text-[10px] font-semibold tracking-widest text-gray-500 uppercase">Publisher</p>
                <p class="mt-1 text-sm text-gray-200">{@book.publisher.name}</p>
              </div>
            <% end %>
            <%= if @book.year do %>
              <div>
                <p class="text-[10px] font-semibold tracking-widest text-gray-500 uppercase">Year</p>
                <p class="mt-1 text-sm text-gray-200">{@book.year}</p>
              </div>
            <% end %>
            <div>
              <p class="text-[10px] font-semibold tracking-widest text-gray-500 uppercase">Age Rating</p>
              <p class="mt-1 text-sm text-gray-200">{format_age_rating(@book.age_rating)}</p>
            </div>
            <div>
              <p class="text-[10px] font-semibold tracking-widest text-gray-500 uppercase">Format</p>
              <p class="mt-1 text-sm text-gray-200">{String.upcase(to_string(@book.format))}</p>
            </div>
            <div>
              <p class="text-[10px] font-semibold tracking-widest text-gray-500 uppercase">File Size</p>
              <p class="mt-1 text-sm text-gray-200">{format_file_size(@book.file_size)}</p>
            </div>
          </div>

          <%!-- Path --%>
          <div class="mt-4">
            <p class="text-[10px] font-semibold tracking-widest text-gray-500 uppercase">Path</p>
            <p class="mt-1 flex items-start gap-1.5 text-sm font-mono text-gray-400 break-all">
              <.icon name="lucide-file" class="w-3.5 h-3.5 flex-shrink-0 mt-0.5 text-gray-500" />
              {relative_path(@book, @library)}
            </p>
          </div>

          <%!-- Summary --%>
          <%= if @book.summary && @book.summary != "" do %>
            <p class="mt-5 text-gray-400 text-sm leading-relaxed">{@book.summary}</p>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
