defmodule StashixWeb.AllPublishersLive do
  use StashixWeb, :live_view

  alias Stashix.Library

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @page_size 24

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Publishers",
       page: 1,
       publishers: [],
       stats_map: %{},
       covers_map: %{},
       total: 0,
       total_pages: 1,
       loading: true
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = max(1, String.to_integer(params["page"] || "1"))
    {:noreply, socket |> assign(page: page) |> load_publishers(page)}
  end

  @impl true
  def handle_event("goto_page", %{"page" => p}, socket) do
    page = String.to_integer(p) |> max(1) |> min(socket.assigns.total_pages)
    {:noreply, push_patch(socket, to: ~p"/publishers?#{%{page: page}}")}
  end

  defp load_publishers(socket, page) do
    total = Library.count_publishers()
    total_pages = max(1, ceil(total / @page_size))

    publishers =
      Library.list_publishers_paginated(limit: @page_size, offset: (page - 1) * @page_size)

    pub_ids = Enum.map(publishers, & &1.id)
    stats_map = Library.publisher_stats(pub_ids)
    covers_map = Library.publisher_sample_covers(pub_ids)

    assign(socket,
      publishers: publishers,
      stats_map: stats_map,
      covers_map: covers_map,
      total: total,
      total_pages: total_pages,
      loading: false
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.browse_header title="Publishers" subtitle={"#{@total} publishers"} />

      <%= if @publishers != [] do %>
        <.pagination page={@page} total_pages={@total_pages} scroll_to="content-list" />

        <div id="content-list" class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
          <%= for pub <- @publishers do %>
            <% stats = Map.get(@stats_map, pub.id, %{series_count: 0, books_count: 0, issues_count: 0}) %>
            <% cover_ids = Map.get(@covers_map, pub.id, []) %>
            <a href={~p"/publisher/#{pub.id}"} class="group block rounded-xl border border-gray-800 bg-gray-900 hover:border-violet-700/60 hover:bg-gray-800/60 overflow-hidden transition-all">
              <%!-- Cover strip --%>
              <div class="flex h-24 bg-gray-950 overflow-hidden">
                <%= if cover_ids == [] do %>
                  <div class="flex-1 flex items-center justify-center">
                    <.icon name="lucide-building-2" class="w-8 h-8 text-gray-700" />
                  </div>
                <% else %>
                  <%= for book_id <- cover_ids do %>
                    <div class="flex-1 relative min-w-0">
                      <img
                        src={~p"/api/books/#{book_id}/cover"}
                        alt=""
                        class="absolute inset-0 w-full h-full object-cover object-top"
                        loading="lazy"
                      />
                    </div>
                  <% end %>
                <% end %>
              </div>

              <%!-- Card body --%>
              <div class="p-3 space-y-2">
                <p class="text-sm font-semibold text-white group-hover:text-violet-200 transition-colors truncate">
                  {pub.name}
                </p>
                <div class="flex flex-wrap gap-1.5">
                  <%= if stats.series_count > 0 do %>
                    <span class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-medium bg-violet-900/40 text-violet-300 border border-violet-800/40">
                      <.icon name="lucide-layers" class="w-2.5 h-2.5" />
                      {stats.series_count} series
                    </span>
                  <% end %>
                  <%= if stats.books_count > 0 do %>
                    <span class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-medium bg-gray-800 text-gray-400 border border-gray-700">
                      <.icon name="lucide-book" class="w-2.5 h-2.5" />
                      {stats.books_count} books
                    </span>
                  <% end %>
                  <%= if stats.issues_count > 0 do %>
                    <span class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-medium bg-gray-800 text-gray-400 border border-gray-700">
                      <.icon name="lucide-newspaper" class="w-2.5 h-2.5" />
                      {stats.issues_count} issues
                    </span>
                  <% end %>
                  <%= if stats.series_count == 0 && stats.books_count == 0 && stats.issues_count == 0 do %>
                    <span class="text-[10px] text-gray-600">No content</span>
                  <% end %>
                </div>
              </div>
            </a>
          <% end %>
        </div>

        <.pagination page={@page} total_pages={@total_pages} scroll_to="content-list" />
      <% end %>

      <%= if !@loading && @publishers == [] do %>
        <.browse_empty icon="lucide-building-2" label="No publishers found." />
      <% end %>
    </div>
    """
  end
end
