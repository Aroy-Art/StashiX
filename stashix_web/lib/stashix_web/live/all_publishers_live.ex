defmodule StashixWeb.AllPublishersLive do
  use StashixWeb, :live_view

  import StashixWeb.CollectionComponents

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
    total = Library.count_publishers(socket.assigns.access)
    total_pages = max(1, ceil(total / @page_size))

    publishers =
      Library.list_publishers_paginated(
        access: socket.assigns.access,
        limit: @page_size,
        offset: (page - 1) * @page_size
      )

    pub_ids = Enum.map(publishers, & &1.id)
    stats_map = Library.publisher_stats(socket.assigns.access, pub_ids)
    covers_map = Library.publisher_sample_covers(socket.assigns.access, pub_ids)

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
  def handle_info({:cover_updated, _}, socket), do: {:noreply, socket}
  def handle_info({:scan_progress, _}, socket), do: {:noreply, socket}
  def handle_info({:book_added, _}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <.page wide>
      <.page_hero title="Publishers" eyebrow="Browse" count={@total > 0 && @total}>
        <:meta>
          <span>
            <span class="text-white font-semibold">{@total}</span>
            {if @total == 1, do: "publisher", else: "publishers"}
          </span>
          <span :if={@total_pages > 1}>page {@page} of {@total_pages}</span>
        </:meta>
      </.page_hero>

      <.pagination id="page-top" page={@page} total_pages={@total_pages} />

      <div :if={@publishers != []} class="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-6 gap-4 scroll-mt-4">
        <% empty = %{series_count: 0, books_count: 0, issues_count: 0} %>
        <.collection_card
          :for={pub <- @publishers}
          navigate={~p"/publisher/#{pub.id}"}
          name={pub.name}
          icon="lucide-building-2"
          covers={for {book_id, _blurhash} <- Map.get(@covers_map, pub.id, []), do: ~p"/api/books/#{book_id}/cover?s=sx"}
          stats={
            stats = Map.get(@stats_map, pub.id, empty)
            [{"series", stats.series_count}, {"books", stats.books_count}, {"issues", stats.issues_count}]
          }
          note="No content"
        />
      </div>

      <.pagination page={@page} total_pages={@total_pages} scroll_to="page-top" />

      <.empty_state :if={!@loading && @publishers == []} ghost="0" title="No publishers yet">
        Publishers appear once metadata has been matched.
      </.empty_state>
    </.page>
    """
  end
end
