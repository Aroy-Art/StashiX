defmodule StashixWeb.SeriesLive do
  use StashixWeb, :live_view

  alias Stashix.Library

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    series = Library.get_series_with_books(id)
    library = Library.get_library!(series.library_id)

    total_pages = Enum.sum(Enum.map(series.books, & &1.page_count))
    total_size = Enum.sum(Enum.map(series.books, & &1.file_size))
    cover_book = List.first(series.books)

    {:ok,
     assign(socket,
       page_title: series.name,
       series: series,
       library: library,
       books: series.books,
       total_pages: total_pages,
       total_size: total_size,
       cover_book: cover_book
     )}
  end

  defp format_file_size(0), do: nil
  defp format_file_size(bytes) when bytes >= 1_073_741_824, do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"
  defp format_file_size(bytes) when bytes >= 1_048_576, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_file_size(bytes) when bytes >= 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_file_size(bytes), do: "#{bytes} B"

  defp year_range(%{start_year: nil}), do: nil
  defp year_range(%{start_year: s, end_year: nil}), do: "#{s}–"
  defp year_range(%{start_year: s, end_year: e}), do: "#{s}–#{e}"

  defp relative_folder(series, library) do
    library.name <> "/" <> (String.replace_prefix(series.path || "", library.root_path, "") |> String.trim_leading("/"))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Breadcrumbs --%>
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
        <span class="text-gray-700">/</span>
        <span class="text-gray-300">{@series.name}</span>
      </div>

      <%!-- Header --%>
      <div class="flex gap-6 md:gap-8">
        <%!-- Cover --%>
        <div class="w-36 md:w-48 flex-shrink-0">
          <div class="aspect-[2/3] bg-gray-800/60 rounded-xl overflow-hidden">
            <%= if @cover_book && @cover_book.cover do %>
              <img
                id={"series-cover-#{@series.id}"}
                phx-hook="CoverImage"
                src={~p"/api/books/#{@cover_book.id}/cover?w=384"}
                alt={@series.name}
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
          <h1 class="text-2xl md:text-3xl font-bold text-white">{@series.name}</h1>

          <%!-- Publisher + year range --%>
          <div class="flex items-center gap-2 mt-1 flex-wrap">
            <%= if @series.publisher do %>
              <span class="text-violet-400 text-sm font-medium">{@series.publisher.name}</span>
            <% end %>
            <%= if yr = year_range(@series) do %>
              <span class="text-gray-500 text-sm">{yr}</span>
            <% end %>
          </div>

          <%!-- Quick stats --%>
          <div class="flex flex-wrap items-center gap-x-5 gap-y-1 mt-3 text-sm text-gray-400">
            <%= if @total_pages > 0 do %>
              <span class="flex items-center gap-1.5">
                <.icon name="lucide-book-open" class="w-4 h-4" />
                {:erlang.integer_to_list(@total_pages) |> List.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")} pages
              </span>
            <% end %>
            <span class="flex items-center gap-1.5">
              <.icon name="lucide-hash" class="w-4 h-4" />
              {length(@books)} issues
            </span>
            <%= if fs = format_file_size(@total_size) do %>
              <span class="flex items-center gap-1.5">
                <.icon name="lucide-hard-drive" class="w-4 h-4" />
                {fs}
              </span>
            <% end %>
          </div>

          <%!-- Read button --%>
          <%= if @cover_book do %>
            <a
              href={~p"/read/#{@cover_book.id}"}
              class="inline-flex items-center gap-2 px-5 py-2.5 mt-4 bg-violet-600 hover:bg-violet-500 text-white text-sm font-medium rounded-lg transition-colors"
            >
              <.icon name="lucide-book-open" class="w-4 h-4" />
              Read
            </a>
          <% end %>

          <%!-- Metadata grid --%>
          <div class="mt-6 grid grid-cols-2 gap-x-8 gap-y-4">
            <%= if @series.publisher do %>
              <div>
                <p class="text-[10px] font-semibold tracking-widest text-gray-500 uppercase">Publisher</p>
                <p class="mt-1 text-sm text-gray-200">{@series.publisher.name}</p>
              </div>
            <% end %>
            <div>
              <p class="text-[10px] font-semibold tracking-widest text-gray-500 uppercase">Issues</p>
              <p class="mt-1 text-sm text-gray-200">{length(@books)}</p>
            </div>
            <%= if yr = year_range(@series) do %>
              <div>
                <p class="text-[10px] font-semibold tracking-widest text-gray-500 uppercase">Years</p>
                <p class="mt-1 text-sm text-gray-200">{yr}</p>
              </div>
            <% end %>
          </div>

          <%!-- Folder --%>
          <%= if @series.path do %>
            <div class="mt-4">
              <p class="text-[10px] font-semibold tracking-widest text-gray-500 uppercase">Folder</p>
              <p class="mt-1 flex items-start gap-1.5 text-sm font-mono text-gray-400 break-all">
                <.icon name="lucide-folder" class="w-3.5 h-3.5 flex-shrink-0 mt-0.5 text-gray-500" />
                {relative_folder(@series, @library)}
              </p>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Books grid --%>
      <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-8 gap-4">
        <%= for book <- @books do %>
          <.media_card
            href={~p"/book/#{book.id}"}
            title={if book.issue_number, do: "##{book.issue_number} – #{book.title}", else: book.title}
            cover_url={~p"/api/books/#{book.id}/cover"}
            width={300}
            subtitle={book.year && to_string(book.year)}
            type={:book}
          />
        <% end %>
      </div>
    </div>
    """
  end
end
