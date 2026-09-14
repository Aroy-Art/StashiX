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

  defp series_date_range(%{start_year: nil}), do: nil
  defp series_date_range(%{start_year: y, end_year: nil, ongoing: true}), do: "#{y}–"
  defp series_date_range(%{start_year: y, end_year: nil}), do: to_string(y)
  defp series_date_range(%{start_year: y, end_year: y}), do: to_string(y)
  defp series_date_range(%{start_year: s, end_year: e}), do: "#{s}–#{e}"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.browse_header title="Series" subtitle={"#{@total} series"}>
        <:controls>
          <.library_filter libraries={@sidebar_libraries} selected_id={@library_id} />
          <.separator orientation="vertical" class="h-5 mx-1" />
          <.sort_select options={@sort_options} selected={@sort} />
        </:controls>
      </.browse_header>

      <%= if @series != [] do %>
        <.pagination id="page-top" page={@page} total_pages={@total_pages} />
        <.media_grid>
          <%= for s <- @series do %>
            <.media_card
              navigate={~p"/series/#{s.id}"}
              title={s.name}
              cover_url={~p"/api/series/#{s.id}/cover"}
              size="m"
              subtitle={series_date_range(s)}
              badge={"#{s.issue_count} issues"}
              type={:series}
              blurhash={s.cover_blurhash}
            />
          <% end %>
        </.media_grid>
        <.pagination page={@page} total_pages={@total_pages} scroll_to="page-top" />
      <% end %>

      <%= if !@loading && @series == [] do %>
        <.browse_empty icon="lucide-book-copy" label="No series found." />
      <% end %>
    </div>
    """
  end
end
