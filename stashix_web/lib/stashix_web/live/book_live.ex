defmodule StashixWeb.BookLive do
  use StashixWeb, :live_view

  alias Stashix.{Formatters, Library, Scanner}
  alias Stashix.Library.Book

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    book = Library.get_book_with_series(id)
    library = Library.get_library!(book.library_id)

    progress = Library.get_progress(socket.assigns.current_user.id, id)
    current_page = (progress && progress.current_page) || 0
    fully_read = book.page_count > 0 && current_page >= book.page_count - 1

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Stashix.PubSub, "scan:#{library.id}")
    end

    {:ok,
     assign(socket,
       page_title: book.title,
       book: book,
       library: library,
       progress: current_page,
       fully_read: fully_read,
       read_menu_open: false,
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
        book = socket.assigns.book
        form = book |> Book.changeset(%{}) |> to_form()
        assign(socket, show_edit_dialog: true, edit_form: form)
      else
        assign(socket, show_edit_dialog: false, edit_form: nil)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_read_menu", _params, socket) do
    {:noreply, assign(socket, read_menu_open: !socket.assigns.read_menu_open)}
  end

  def handle_event("close_read_menu", _params, socket) do
    {:noreply, assign(socket, read_menu_open: false)}
  end

  def handle_event("mark_unread", _params, socket) do
    Library.update_progress(socket.assigns.current_user.id, socket.assigns.book.id, 0)
    {:noreply, assign(socket, progress: 0, fully_read: false, read_menu_open: false)}
  end

  def handle_event("toggle_admin_menu", _params, socket) do
    {:noreply, assign(socket, show_admin_menu: !socket.assigns.show_admin_menu)}
  end

  def handle_event("open_edit_dialog", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/book/#{socket.assigns.book.id}?edit=true")}
  end

  def handle_event("close_edit_dialog", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/book/#{socket.assigns.book.id}")}
  end

  def handle_event("save_metadata", %{"book" => params}, socket) do
    book = socket.assigns.book

    case Library.update_book(book, params) do
      {:ok, updated_book} ->
        book = Library.get_book_with_series(updated_book.id)

        {:noreply,
         socket
         |> assign(book: book, page_title: book.title)
         |> push_patch(to: ~p"/book/#{book.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, edit_form: to_form(changeset))}
    end
  end

  def handle_event("rescan_book", _params, socket) do
    book = socket.assigns.book
    Scanner.scan_file(book.library_id, book.path)
    {:noreply, assign(socket, scanning: true, show_admin_menu: false)}
  end

  @impl true
  def handle_info({:scan_progress, %{done: true}}, socket) do
    book = Library.get_book_with_series(socket.assigns.book.id)
    progress = Library.get_progress(socket.assigns.current_user.id, book.id)
    current_page = (progress && progress.current_page) || 0
    fully_read = book.page_count > 0 && current_page >= book.page_count - 1

    {:noreply,
     assign(socket,
       scanning: false,
       book: book,
       progress: current_page,
       fully_read: fully_read,
       page_title: book.title
     )}
  end

  def handle_info({:scan_progress, _}, socket), do: {:noreply, socket}
  def handle_info({:book_added, _}, socket), do: {:noreply, socket}

  defp book_display_title(book), do: book.title

  defp relative_path(book, library) do
    library.name <> "/" <> (String.replace_prefix(book.path, library.root_path, "") |> String.trim_leading("/"))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto space-y-8">
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
          <%= if @book.series do %>
            <span class="text-gray-700 flex-shrink-0">/</span>
            <a href={~p"/series/#{@book.series.id}"} class="text-gray-500 hover:text-gray-300 flex-shrink-0">{@book.series.name}</a>
          <% end %>
          <span class="text-gray-700 flex-shrink-0">/</span>
          <span class="text-gray-300 truncate min-w-0">
            <%= if @book.issue_number do %>
              <span class="hidden sm:inline">Issue </span>#<%= Decimal.to_integer(@book.issue_number) %>
            <% else %>
              {@book.title}
            <% end %>
          </span>
        </div>
        <%= if @current_user.role == :admin do %>
          <div class="ml-auto">
            <.dropdown_menu id="book-admin-menu">
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
                  class="hover:bg-gray-700 focus:bg-gray-700 text-gray-300 disabled:opacity-50"
                  on-select={JS.push("rescan_book")}
                >
                  <%= if @scanning do %>
                    <.icon name="lucide-loader-circle" class="w-4 h-4 mr-2 animate-spin text-violet-400" />
                    Scanning…
                  <% else %>
                    <.icon name="lucide-refresh-cw" class="w-4 h-4 mr-2" />
                    Rescan Book
                  <% end %>
                </.dropdown_menu_item>
              </.dropdown_menu_content>
            </.dropdown_menu>
          </div>
        <% end %>
      </div>

      <%!-- Editorial header — cover floats left, info BFC beside it, summary wraps below --%>
      <div class="overflow-hidden">

        <%!-- Cover — floated left --%>
        <div style="float:left; margin-right:2rem; margin-bottom:1rem;" class="w-40 md:w-52">
          <div class="rounded-lg overflow-hidden shadow-[0_8px_40px_rgba(0,0,0,0.65)] aspect-[2/3]">
            <%= if @book.cover do %>
              <img
                id={"book-cover-#{@book.id}"}
                phx-hook="CoverImage"
                src={~p"/api/books/#{@book.id}/cover?w=384"}
                alt={@book.title}
                class="w-full h-full object-cover block"
              />
            <% else %>
              <div class="w-full h-full flex items-center justify-center bg-gray-800/60 text-gray-600">
                <.icon name="lucide-layers" class="w-10 h-10 md:w-14 md:h-14" />
              </div>
            <% end %>
          </div>
        </div>

        <%!-- BFC wrapper: forced beside the float --%>
        <div class="overflow-hidden pt-1">

          <%!-- Series eyebrow --%>
          <%= if @book.series do %>
            <p class="text-[10px] font-bold tracking-[0.18em] uppercase text-violet-400 mb-2">
              <a href={~p"/series/#{@book.series.id}"} class="hover:text-violet-300 transition-colors">
                {@book.series.name}
              </a>
              <%= if @book.series.start_year do %>
                <span class="text-violet-800 normal-case tracking-normal font-normal ml-1">
                  (<%= @book.series.start_year %><%= cond do
                    @book.series.end_year -> "–#{@book.series.end_year}"
                    @book.series.ongoing -> "–"
                    true -> ""
                  end %>)
                </span>
              <% end %>
            </p>
          <% end %>

          <%!-- Title --%>
          <h1 class="text-2xl md:text-3xl font-bold text-white tracking-tight leading-tight mb-3">
            <%= if @book.issue_number do %>#<%= Decimal.to_integer(@book.issue_number) %> – <% end %>{book_display_title(@book)}
          </h1>

          <%!-- Status row --%>
          <div class="flex items-center flex-wrap gap-2 mb-5">
            <%= if @book.year do %>
              <span class="text-sm text-gray-400">{@book.year}</span>
              <span class="text-gray-700 select-none">·</span>
            <% end %>
            <%= if @book.page_count > 0 do %>
              <span class="text-sm text-gray-400">{@book.page_count} pages</span>
              <span class="text-gray-700 select-none">·</span>
            <% end %>
            <%= if @fully_read do %>
              <.badge class="bg-emerald-500/15 text-emerald-400 border-emerald-500/20 gap-1">
                <.icon name="lucide-check" class="w-3 h-3" />
                Read
              </.badge>
            <% else %>
              <%= if @progress > 0 && @book.page_count > 0 do %>
                <span class="text-sm text-gray-400">{@progress}/{@book.page_count} pages</span>
              <% end %>
            <% end %>
          </div>

          <%!-- Progress bar --%>
          <%= if !@fully_read && @progress > 0 && @book.page_count > 0 do %>
            <.progress value={round(@progress / @book.page_count * 100)} class="h-1 [&>div]:bg-violet-500 bg-gray-800 mb-5 rounded-full" />
          <% end %>

          <%!-- Read button --%>
          <%= if @book.page_count > 0 do %>
            <div class="flex items-center gap-0">
              <a
                href={if @fully_read, do: ~p"/read/#{@book.id}?page=0", else: ~p"/read/#{@book.id}"}
                class={[
                  "inline-flex items-center gap-2 px-5 py-2.5 bg-violet-600 hover:bg-violet-500 text-white text-sm font-semibold transition-colors",
                  if(@progress > 0, do: "rounded-l-lg", else: "rounded-lg")
                ]}
              >
                <.icon name="lucide-play" class="w-4 h-4" />
                {cond do
                  @fully_read -> "Read Again"
                  @progress > 0 -> "Continue"
                  true -> "Read"
                end}
              </a>
              <%= if @progress > 0 do %>
                <.dropdown_menu id="read-options-menu" class="flex">
                  <.dropdown_menu_trigger class="flex items-center self-stretch px-2 bg-violet-700 hover:bg-violet-600 text-white rounded-r-lg border-l border-violet-500 transition-colors">
                    <.icon name="lucide-chevron-down" class="w-4 h-4" />
                  </.dropdown_menu_trigger>
                  <.dropdown_menu_content align="end" class="bg-gray-800 border-gray-700 min-w-48">
                    <%= if !@fully_read do %>
                      <.dropdown_menu_item class="hover:bg-gray-700 focus:bg-gray-700 text-gray-300 p-0">
                        <a href={~p"/read/#{@book.id}?page=0"} class="flex items-center gap-2 px-2 py-1.5 w-full">
                          <.icon name="lucide-rotate-ccw" class="w-4 h-4" />
                          Read from Beginning
                        </a>
                      </.dropdown_menu_item>
                    <% end %>
                    <.dropdown_menu_item
                      class="hover:bg-gray-700 focus:bg-gray-700 text-gray-300"
                      on-select={JS.push("mark_unread")}
                    >
                      <.icon name="lucide-circle-x" class="w-4 h-4 mr-2" />
                      Mark as Unread
                    </.dropdown_menu_item>
                  </.dropdown_menu_content>
                </.dropdown_menu>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Summary — outside BFC, wraps around float then expands to full width --%>
        <%= if @book.summary && @book.summary != "" do %>
          <p class="text-sm text-gray-400 leading-relaxed mt-5">{@book.summary}</p>
        <% end %>
      </div>

      <%!-- Full-width metadata strip --%>
      <div class="flex flex-wrap gap-px bg-gray-800 rounded-lg overflow-hidden text-xs">
        <%= if @book.publishers != [] do %>
          <div class="flex-1 min-w-[9rem] bg-gray-900 px-4 py-3">
            <p class="text-[9px] font-bold tracking-[0.14em] uppercase text-gray-600 mb-1">Publisher</p>
            <p class="text-gray-300">
              <%= for {pub, idx} <- Enum.with_index(@book.publishers) do %>
                <%= if idx > 0 do %><span class="text-gray-600"> / </span><% end %>
                <a href={~p"/publisher/#{pub.id}"} class="hover:text-violet-400 transition-colors">{pub.name}</a>
              <% end %>
            </p>
          </div>
        <% end %>
        <%= if @book.year do %>
          <div class="flex-1 min-w-[6rem] bg-gray-900 px-4 py-3">
            <p class="text-[9px] font-bold tracking-[0.14em] uppercase text-gray-600 mb-1">Year</p>
            <p class="text-gray-300">{@book.year}</p>
          </div>
        <% end %>
        <%= if @book.page_count > 0 do %>
          <div class="flex-1 min-w-[6rem] bg-gray-900 px-4 py-3">
            <p class="text-[9px] font-bold tracking-[0.14em] uppercase text-gray-600 mb-1">Pages</p>
            <p class="text-gray-300">{@book.page_count}</p>
          </div>
        <% end %>
        <div class="flex-1 min-w-[6rem] bg-gray-900 px-4 py-3">
          <p class="text-[9px] font-bold tracking-[0.14em] uppercase text-gray-600 mb-1">Format</p>
          <p class="text-gray-300">{String.upcase(to_string(@book.format))}</p>
        </div>
        <%= if fs = Formatters.format_file_size(@book.file_size) do %>
          <div class="flex-1 min-w-[6rem] bg-gray-900 px-4 py-3">
            <p class="text-[9px] font-bold tracking-[0.14em] uppercase text-gray-600 mb-1">Size</p>
            <p class="text-gray-300">{fs}</p>
          </div>
        <% end %>
        <%= if @book.language do %>
          <div class="flex-1 min-w-[6rem] bg-gray-900 px-4 py-3">
            <p class="text-[9px] font-bold tracking-[0.14em] uppercase text-gray-600 mb-1">Language</p>
            <p class="text-gray-300">{Formatters.language_name(@book.language)}</p>
          </div>
        <% end %>
        <div class="flex-1 min-w-[6rem] bg-gray-900 px-4 py-3">
          <p class="text-[9px] font-bold tracking-[0.14em] uppercase text-gray-600 mb-1">Age Rating</p>
          <p class="text-gray-300">{Formatters.format_age_rating(@book.age_rating)}</p>
        </div>
      </div>

      <%!-- File path --%>
      <%= if @current_user.role == :admin do %>
        <div class="flex items-start gap-1.5 text-[11px] font-mono text-gray-600 break-all leading-snug -mt-4">
          <.icon name="lucide-file" class="w-3 h-3 flex-shrink-0 mt-0.5 text-gray-700" />
          {relative_path(@book, @library)}
        </div>
      <% end %>
    </div>

    <%!-- Edit Metadata Dialog --%>
    <%= if @current_user.role == :admin && @show_edit_dialog do %>
      <.dialog id="edit-metadata-dialog" open={true} on-close={JS.push("close_edit_dialog")}>
        <.dialog_content class="sm:max-w-xl !bg-gray-900 !border-gray-700 text-white">
          <.dialog_header>
            <.dialog_title class="text-white">Edit Metadata</.dialog_title>
            <.dialog_description class="text-gray-400">
              Override metadata for this book. Changes persist until the next rescan.
            </.dialog_description>
            <p class="flex items-center gap-1.5 text-xs font-mono text-gray-500 mt-1 break-all">
              <.icon name="lucide-file" class="w-3 h-3 flex-shrink-0" />
              {relative_path(@book, @library)}
            </p>
          </.dialog_header>

          <.form for={@edit_form} phx-submit="save_metadata" class="space-y-3 mt-2">
            <div class="grid grid-cols-2 gap-x-4 gap-y-3">
              <div class="col-span-2">
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Title</label>
                <input
                  type="text"
                  name="book[title]"
                  value={@edit_form[:title].value}
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Issue #</label>
                <input
                  type="text"
                  name="book[issue_number]"
                  value={@edit_form[:issue_number].value}
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Volume</label>
                <input
                  type="number"
                  name="book[volume]"
                  value={@edit_form[:volume].value}
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Year</label>
                <input
                  type="number"
                  name="book[year]"
                  value={@edit_form[:year].value}
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Language</label>
                <input
                  type="text"
                  name="book[language]"
                  value={@edit_form[:language].value}
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                />
              </div>

              <div class="col-span-2">
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Age Rating</label>
                <select
                  name="book[age_rating]"
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
                >
                  <%= for {label, val} <- [{"Unknown", "unknown"}, {"Everyone", "everyone"}, {"Teen", "teen"}, {"Teen+", "teen_plus"}, {"Mature", "mature"}, {"Adult", "adult"}, {"Explicit", "explicit"}] do %>
                    <option value={val} selected={to_string(@edit_form[:age_rating].value) == val}>{label}</option>
                  <% end %>
                </select>
              </div>

              <div class="col-span-2">
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Summary</label>
                <textarea
                  name="book[summary]"
                  rows="4"
                  class="w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500 resize-none"
                >{@edit_form[:summary].value}</textarea>
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
