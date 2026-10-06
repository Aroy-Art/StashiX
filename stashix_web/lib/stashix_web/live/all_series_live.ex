defmodule StashixWeb.AllSeriesLive do
  use StashixWeb, :live_view

  alias Stashix.Library

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @page_size 48

  @sort_options [
    {"A → Z", "title_asc"},
    {"Z → A", "title_desc"},
    {"Year ↑", "year_asc"},
    {"Year ↓", "year_desc"},
    {"Date Added ↓", "added_desc"},
    {"Date Added ↑", "added_asc"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "All Series",
       sort: "title_asc",
       library_id: nil,
       page: 1,
       series: [],
       total: 0,
       total_pages: 1,
       loading: true,
       sort_options: @sort_options
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = max(1, String.to_integer(params["page"] || "1"))
    sort = params["sort"] || socket.assigns.sort
    library_id = params["library"] || nil

    {:noreply,
     socket
     |> assign(page: page, sort: sort, library_id: library_id)
     |> load_series(page)}
  end

  @impl true
  def handle_event("filter_library", %{"id" => id}, socket) do
    library_id = if id == "", do: nil, else: id
    {:noreply, push_patch(socket, to: build_path(1, socket.assigns.sort, library_id))}
  end

  def handle_event("sort", %{"value" => sort}, socket) do
    {:noreply, push_patch(socket, to: build_path(1, sort, socket.assigns.library_id))}
  end

  def handle_event("goto_page", %{"page" => p}, socket) do
    page = String.to_integer(p) |> max(1) |> min(socket.assigns.total_pages)

    {:noreply, push_patch(socket, to: build_path(page, socket.assigns.sort, socket.assigns.library_id))}
  end

  defp build_path(page, sort, library_id) do
    params = %{page: page, sort: sort}
    params = if library_id, do: Map.put(params, :library, library_id), else: params
    ~p"/series?#{params}"
  end

  defp load_series(socket, page) do
    opts = [
      access: socket.assigns.access,
      sort: socket.assigns.sort,
      library_id: socket.assigns.library_id,
      limit: @page_size,
      offset: (page - 1) * @page_size
    ]

    series = Library.list_all_series(opts)
    total = Library.count_all_series(opts)
    total_pages = max(1, ceil(total / @page_size))

    assign(socket, series: series, total: total, total_pages: total_pages, loading: false)
  end

  @impl true
  def handle_info({:cover_updated, _}, socket), do: {:noreply, socket}
  def handle_info({:scan_progress, _}, socket), do: {:noreply, socket}
  def handle_info({:book_added, _}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <% first = List.first(@series) %>
    <.page wide fade cover_src={first && ~p"/api/series/#{first.id}/cover?s=s"}>
      <.page_hero title="Series" eyebrow="Browse" count={@total > 0 && @total}>
        <:meta>
          <span>
            <span class="text-white font-semibold">{@total}</span>
            {if @total == 1, do: "series", else: "series"}
          </span>
          <span :if={@total_pages > 1}>page {@page} of {@total_pages}</span>
        </:meta>
      </.page_hero>

      <.browse_toolbar
        libraries={@sidebar_libraries}
        library_id={@library_id}
        sort_options={@sort_options}
        sort={@sort}
      />

      <%= if @series != [] do %>
        <.pagination id="page-top" page={@page} total_pages={@total_pages} />
        <.cover_grid>
          <%= for s <- @series do %>
            <.series_card series={s} />
          <% end %>
        </.cover_grid>
        <.pagination page={@page} total_pages={@total_pages} scroll_to="page-top" />
      <% end %>

      <.empty_state :if={!@loading && @series == []} ghost="0" title="No series on this shelf">
        {if @library_id, do: "Nothing in this library yet. Try another one.", else: "Scan a library to fill it."}
      </.empty_state>
    </.page>
    """
  end
end
