defmodule StashixWeb.SeriesLive do
  use StashixWeb, :live_view

  alias Stashix.{Library, Scanner}
  alias Stashix.Library.Series

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    series = Library.get_series_with_books(id)
    library = Library.get_library!(series.library_id)

    total_pages = Enum.sum(Enum.map(series.books, & &1.page_count))
    total_size = Enum.sum(Enum.map(series.books, & &1.file_size))
    sort = "issue_asc"
    books = sort_books(series.books, sort)
    cover_book = List.first(books)
    book_ids = Enum.map(series.books, & &1.id)
    progress_map = Library.progress_map(socket.assigns.current_user.id, book_ids)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Stashix.PubSub, "scan:#{library.id}")
    end

    {:ok,
     assign(socket,
       page_title: series.name,
       series: series,
       library: library,
       books: books,
       sort: sort,
       progress_map: progress_map,
       total_pages: total_pages,
       total_size: total_size,
       cover_book: cover_book,
       scanning: false,
       show_admin_menu: false,
       show_edit_dialog: false,
       edit_form: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      if params["edit"] == "true" && socket.assigns.current_user.role == :admin do
        series = socket.assigns.series
        form = series |> Series.changeset(%{}) |> to_form()
        assign(socket, show_edit_dialog: true, edit_form: form)
      else
        assign(socket, show_edit_dialog: false, edit_form: nil)
      end

    {:noreply, socket}
  end

  defp format_file_size(0), do: nil
  defp format_file_size(bytes) when bytes >= 1_073_741_824, do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"
  defp format_file_size(bytes) when bytes >= 1_048_576, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_file_size(bytes) when bytes >= 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_file_size(bytes), do: "#{bytes} B"

  defp year_range(%{start_year: nil}), do: nil
  defp year_range(%{start_year: s, end_year: nil, ongoing: true}), do: "#{s}–"
  defp year_range(%{start_year: s, end_year: nil}), do: "#{s}"
  defp year_range(%{start_year: s, end_year: e}), do: "#{s}–#{e}"

  defp relative_folder(series, library) do
    library.name <> "/" <> (String.replace_prefix(series.path || "", library.root_path, "") |> String.trim_leading("/"))
  end

  @impl true
  def handle_event("sort", %{"value" => sort}, socket) do
    {:noreply, assign(socket, sort: sort, books: sort_books(socket.assigns.series.books, sort))}
  end

  def handle_event("toggle_admin_menu", _, socket) do
    {:noreply, assign(socket, show_admin_menu: !socket.assigns.show_admin_menu)}
  end

  def handle_event("open_edit_dialog", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/series/#{socket.assigns.series.id}?edit=true")}
  end

  def handle_event("close_edit_dialog", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/series/#{socket.assigns.series.id}")}
  end

  def handle_event("save_metadata", %{"series" => params}, socket) do
    series = socket.assigns.series

    case Library.update_series(series, params) do
      {:ok, updated_series} ->
        series = Library.get_series_with_books(updated_series.id)

        {:noreply,
         socket
         |> assign(series: series, page_title: series.name)
         |> push_patch(to: ~p"/series/#{series.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, edit_form: to_form(changeset))}
    end
  end

  def handle_event("rescan_series", _, socket) do
    Scanner.scan_series(socket.assigns.series.id)
    {:noreply, assign(socket, scanning: true, show_admin_menu: false)}
  end

  def handle_event("force_rescan_series", _, socket) do
    Scanner.scan_series(socket.assigns.series.id, true)
    {:noreply, assign(socket, scanning: true, show_admin_menu: false)}
  end

  @impl true
  def handle_info({:scan_progress, %{done: true}}, socket) do
    series = Library.get_series_with_books(socket.assigns.series.id)
    books = sort_books(series.books, socket.assigns.sort)
    book_ids = Enum.map(series.books, & &1.id)
    progress_map = Library.progress_map(socket.assigns.current_user.id, book_ids)
    total_pages = Enum.sum(Enum.map(series.books, & &1.page_count))
    total_size = Enum.sum(Enum.map(series.books, & &1.file_size))

    {:noreply,
     assign(socket,
       scanning: false,
       series: series,
       books: books,
       progress_map: progress_map,
       total_pages: total_pages,
       total_size: total_size,
       cover_book: List.first(books)
     )}
  end

  def handle_info({:scan_progress, _}, socket), do: {:noreply, socket}
  def handle_info({:book_added, _}, socket), do: {:noreply, socket}

  defp sort_books(books, "title_asc"), do: Enum.sort_by(books, & &1.title)
  defp sort_books(books, "title_desc"), do: Enum.sort_by(books, & &1.title, :desc)
  defp sort_books(books, "year_asc"), do: Enum.sort_by(books, &(&1.year || 0))
  defp sort_books(books, "year_desc"), do: Enum.sort_by(books, &(&1.year || 0), :desc)
  defp sort_books(books, "added_asc"), do: Enum.sort_by(books, & &1.inserted_at, NaiveDateTime)
  defp sort_books(books, "added_desc"), do: Enum.sort_by(books, & &1.inserted_at, {:desc, NaiveDateTime})

  defp sort_books(books, "issue_desc") do
    Enum.sort_by(books, fn b ->
      if b.issue_number, do: Decimal.to_float(b.issue_number), else: -1.0
    end, :desc)
  end

  defp sort_books(books, _) do
    Enum.sort_by(books, fn b ->
      if b.issue_number, do: Decimal.to_float(b.issue_number), else: 999_999.0
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Breadcrumbs --%>
      <div class="flex flex-wrap items-center gap-x-2 gap-y-3 text-sm">
        <button onclick="history.back()" class="flex items-center gap-1 px-2.5 py-1 rounded-md border border-white/20 text-gray-300 hover:border-white/40 hover:text-white transition-colors flex-shrink-0">
          <.icon name="lucide-chevron-left" class="w-4 h-4" />
          Back
        </button>
        <div class="flex items-center gap-2 w-full sm:w-auto sm:flex-1 min-w-0 overflow-hidden order-first sm:order-none">
          <a href="/" class="text-gray-500 hover:text-gray-300 flex-shrink-0">Home</a>
          <span class="text-gray-700 flex-shrink-0">/</span>
          <a href={~p"/library/#{@library.id}"} class="text-gray-500 hover:text-gray-300 flex-shrink-0">{@library.name}</a>
          <span class="text-gray-700 flex-shrink-0">/</span>
          <span class="text-gray-300 truncate min-w-0">{@series.name}</span>
        </div>
        <%= if @current_user.role == :admin do %>
          <div class="ml-auto">
            <.dropdown_menu id="series-admin-menu">
              <.dropdown_menu_trigger class="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg bg-gray-800 hover:bg-gray-700 text-gray-400 hover:text-gray-200 border border-gray-700 transition-colors">
                <.icon name="lucide-settings" class="w-3.5 h-3.5" />
                Admin
                <.icon name="lucide-chevron-down" class="w-3 h-3" />
              </.dropdown_menu_trigger>
              <.dropdown_menu_content align="end" class="bg-gray-800 border-gray-700 min-w-44">
                <.dropdown_menu_item
                  class="hover:bg-gray-700 focus:bg-gray-700 text-gray-300"
                  on-select={JS.push("open_edit_dialog")}
                >
                  <.icon name="lucide-pencil" class="w-4 h-4 mr-2" />
                  Edit Metadata
                </.dropdown_menu_item>
                <.dropdown_menu_item
                  class="hover:bg-gray-700 focus:bg-gray-700 text-gray-300"
                  on-select={JS.push("rescan_series")}
                >
                  <%= if @scanning do %>
                    <.icon name="lucide-loader-circle" class="w-4 h-4 mr-2 animate-spin text-violet-400" />
                    Scanning…
                  <% else %>
                    <.icon name="lucide-refresh-cw" class="w-4 h-4 mr-2" />
                    Rescan Series
                  <% end %>
                </.dropdown_menu_item>
                <.dropdown_menu_item
                  class="hover:bg-gray-700 focus:bg-gray-700 text-amber-400"
                  on-select={JS.push("force_rescan_series")}
                >
                  <%= if @scanning do %>
                    <.icon name="lucide-loader-circle" class="w-4 h-4 mr-2 animate-spin" />
                    Scanning…
                  <% else %>
                    <.icon name="lucide-zap" class="w-4 h-4 mr-2" />
                    Force Rescan
                  <% end %>
                </.dropdown_menu_item>
              </.dropdown_menu_content>
            </.dropdown_menu>
          </div>
        <% end %>
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
            <%= if @series.publishers != [] do %>
              <span class="text-sm font-medium">
                <%= for {pub, idx} <- Enum.with_index(@series.publishers) do %>
                  <%= if idx > 0 do %><span class="text-gray-500"> / </span><% end %>
                  <a href={~p"/publisher/#{pub.id}"} class="text-violet-400 hover:text-violet-300 transition-colors">{pub.name}</a>
                <% end %>
              </span>
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
            <%= if @series.publishers != [] do %>
              <div>
                <p class="text-[10px] font-semibold tracking-widest text-gray-500 uppercase">Publisher</p>
                <p class="mt-1 text-sm text-gray-200">
                  <%= for {pub, idx} <- Enum.with_index(@series.publishers) do %>
                    <%= if idx > 0 do %><span class="text-gray-500"> / </span><% end %>
                    <a href={~p"/publisher/#{pub.id}"} class="hover:text-violet-400 transition-colors">{pub.name}</a>
                  <% end %>
                </p>
              </div>
            <% end %>
            <div>
              <p class="text-[10px] font-semibold tracking-widest text-gray-500 uppercase">Issues</p>
              <p class="mt-1 text-sm text-gray-200">{length(@books)}</p>
            </div>
            <div>
              <p class="text-[10px] font-semibold tracking-widest text-gray-500 uppercase">Status</p>
              <%= if @series.ongoing do %>
                <.badge class="mt-1 bg-emerald-500/15 text-emerald-400 border-emerald-500/20 gap-1">
                  <span class="w-1.5 h-1.5 rounded-full bg-emerald-400 inline-block"></span>
                  Ongoing
                </.badge>
              <% else %>
                <.badge variant="outline" class="mt-1 text-gray-400 border-gray-600 gap-1">
                  <span class="w-1.5 h-1.5 rounded-full bg-gray-500 inline-block"></span>
                  Completed
                </.badge>
              <% end %>
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
      <div class="flex items-center justify-between mb-1">
        <h2 class="text-lg font-semibold text-gray-300">{length(@books)} Issues</h2>
        <form phx-change="sort">
          <select
            name="value"
            class="px-3 py-1 text-sm rounded-lg border bg-gray-800 border-gray-700 text-gray-400 hover:text-white focus:outline-none focus:border-indigo-500 cursor-pointer"
          >
            <%= for {label, value} <- [
              {"Issue # ↑", "issue_asc"},
              {"Issue # ↓", "issue_desc"},
              {"A → Z", "title_asc"},
              {"Z → A", "title_desc"},
              {"Year ↑", "year_asc"},
              {"Year ↓", "year_desc"},
              {"Date Added ↓", "added_desc"},
              {"Date Added ↑", "added_asc"}
            ] do %>
              <option value={value} selected={@sort == value}>{label}</option>
            <% end %>
          </select>
        </form>
      </div>
      <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-4 lg:grid-cols-6 xl:grid-cols-8 gap-4">
        <%= for book <- @books do %>
          <% prog = @progress_map[book.id] %>
          <% progress = if prog && book.page_count && book.page_count > 1, do: prog / (book.page_count - 1), else: nil %>
          <.media_card
            href={~p"/book/#{book.id}"}
            title={if book.issue_number, do: "##{book.issue_number} – #{book.title}", else: book.title}
            cover_url={~p"/api/books/#{book.id}/cover"}
            width={300}
            subtitle={book.year && to_string(book.year)}
            progress={progress}
            type={:book}
          />
        <% end %>
      </div>
    </div>

    <%!-- Edit Metadata Dialog --%>
    <%= if @current_user.role == :admin && @show_edit_dialog do %>
      <.dialog id="edit-series-dialog" open={true} on-close={JS.push("close_edit_dialog")}>
        <.dialog_content class="sm:max-w-xl !bg-gray-900 !border-gray-700 text-white">
          <.dialog_header>
            <.dialog_title class="text-white">Edit Series Metadata</.dialog_title>
            <.dialog_description class="text-gray-400">
              Override metadata for this series. Changes persist until the next rescan.
            </.dialog_description>
            <%= if @series.path do %>
              <p class="flex items-center gap-1.5 text-xs font-mono text-gray-500 mt-1 break-all">
                <.icon name="lucide-folder" class="w-3 h-3 flex-shrink-0" />
                {relative_folder(@series, @library)}
              </p>
            <% end %>
          </.dialog_header>

          <.form for={@edit_form} phx-submit="save_metadata" class="space-y-3 mt-2">
            <div class="grid grid-cols-2 gap-x-4 gap-y-3">
              <div class="col-span-2">
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Name</label>
                <input
                  type="text"
                  name="series[name]"
                  value={@edit_form[:name].value}
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Volume</label>
                <input
                  type="number"
                  name="series[volume]"
                  value={@edit_form[:volume].value}
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Language</label>
                <input
                  type="text"
                  name="series[language]"
                  value={@edit_form[:language].value}
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Start Year</label>
                <input
                  type="number"
                  name="series[start_year]"
                  value={@edit_form[:start_year].value}
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-gray-400 mb-1.5">End Year</label>
                <input
                  type="number"
                  name="series[end_year]"
                  value={@edit_form[:end_year].value}
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                />
              </div>

              <div class="col-span-2 flex items-center gap-3">
                <input
                  type="hidden"
                  name="series[ongoing]"
                  value="false"
                />
                <input
                  type="checkbox"
                  id="series_ongoing"
                  name="series[ongoing]"
                  value="true"
                  checked={@edit_form[:ongoing].value}
                  class="rounded border-gray-600 bg-gray-800 text-violet-500 focus:ring-violet-500"
                />
                <label for="series_ongoing" class="text-sm text-gray-300 cursor-pointer">Ongoing series</label>
              </div>
            </div>

            <.dialog_footer class="pt-2">
              <button type="button" phx-click="close_edit_dialog" class="inline-flex items-center justify-center rounded-md px-4 py-2 text-sm font-medium border border-red-700 text-red-400 bg-transparent hover:bg-red-900/30 hover:text-red-300 transition-colors">
                Cancel
              </button>
              <button type="submit" class="inline-flex items-center justify-center rounded-md px-4 py-2 text-sm font-medium bg-emerald-600 hover:bg-emerald-500 text-white transition-colors">
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
