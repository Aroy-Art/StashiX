defmodule StashixWeb.CollectionComponents do
  @moduledoc """
  Page layout shared by the things that hold series, books and issues: a
  library and a publisher. One overview (figures plus a shelf per kind) and
  one paginated grid per kind.
  """
  use Phoenix.Component

  import StashixWeb.CoreComponents
  import StashixWeb.UI.Icon, only: [icon: 1]
  import StashixWeb.UI.Ink
  import StashixWeb.UI.Page

  @doc """
  `live_action` picks the view: `:show` is the overview, `:series`, `:books`
  and `:issues` are the grids (which read `items`, `total` and the paging and
  sort attrs). `:meta` adds a line under the title on the overview.
  """
  attr :name, :string, required: true
  attr :kind, :string, required: true, doc: ~s("Library" or "Publisher")
  attr :base_path, :string, required: true
  attr :live_action, :atom, required: true
  attr :series_count, :integer, default: 0
  attr :books_count, :integer, default: 0
  attr :issues_count, :integer, default: 0
  attr :recent_series, :list, default: []
  attr :recent_books, :list, default: []
  attr :recent_issues, :list, default: []
  attr :items, :list, default: []
  attr :total, :integer, default: 0
  attr :page, :integer, default: 1
  attr :total_pages, :integer, default: 1
  attr :sort_options, :list, default: []
  attr :sort, :string, default: nil
  attr :progress_map, :map, default: %{}
  attr :loading, :boolean, default: false
  attr :empty_hint, :string, default: nil
  slot :meta

  def collection_page(%{live_action: :show} = assigns) do
    assigns =
      assign(assigns,
        cover_src: overview_cover(assigns),
        empty?: assigns.series_count == 0 and assigns.books_count == 0 and assigns.issues_count == 0
      )

    ~H"""
    <.page wide cover_src={@cover_src}>
      <.crumbs crumbs={[{"Home", "/"}, {@name, nil}]} />

      <.page_hero title={@name} eyebrow={@kind}>
        <:meta :if={@meta != []}>{render_slot(@meta)}</:meta>
      </.page_hero>

      <.panel :if={!@empty?} variant="indicia">
        <.stat_list class="px-6 py-5">
          <.stat :if={@series_count > 0} label="Series" navigate={"#{@base_path}/series"}>{@series_count}</.stat>
          <.stat :if={@books_count > 0} label="Books" navigate={"#{@base_path}/books"}>{@books_count}</.stat>
          <.stat :if={@issues_count > 0} label="Issues" navigate={"#{@base_path}/issues"}>{@issues_count}</.stat>
        </.stat_list>
      </.panel>

      <.shelf :if={@recent_series != []} id="collection-series" title="Series" count={@series_count}>
        <:actions><.view_all :if={@series_count > 20} to={"#{@base_path}/series"} /></:actions>
        <.series_card :for={s <- @recent_series} series={s} class="flex-shrink-0 w-36" />
      </.shelf>

      <.shelf :if={@recent_books != []} id="collection-books" title="Books" count={@books_count}>
        <:actions><.view_all :if={@books_count > 20} to={"#{@base_path}/books"} /></:actions>
        <.book_card :for={b <- @recent_books} book={b} class="flex-shrink-0 w-36" />
      </.shelf>

      <.shelf :if={@recent_issues != []} id="collection-issues" title="Issues" count={@issues_count}>
        <:actions><.view_all :if={@issues_count > 20} to={"#{@base_path}/issues"} /></:actions>
        <.book_card :for={b <- @recent_issues} book={b} as={:issue} class="flex-shrink-0 w-36" />
      </.shelf>

      <.empty_state :if={@empty?} ghost="0" title={"Nothing in this #{String.downcase(@kind)}"}>
        {@empty_hint}
      </.empty_state>
    </.page>
    """
  end

  def collection_page(assigns) do
    assigns =
      assign(assigns,
        section: section_label(assigns.live_action),
        cover_src: grid_cover(assigns)
      )

    ~H"""
    <.page wide fade cover_src={@cover_src}>
      <.crumbs crumbs={[{"Home", "/"}, {@name, @base_path}, {@section, nil}]} />

      <.page_hero title={@section} eyebrow={@name} count={@total > 0 && @total}>
        <:meta>
          <span><span class="text-white font-semibold">{@total}</span> {String.downcase(@section)}</span>
          <span :if={@total_pages > 1}>page {@page} of {@total_pages}</span>
        </:meta>
      </.page_hero>

      <.browse_toolbar sort_options={@sort_options} sort={@sort} />

      <.pagination id="page-top" page={@page} total_pages={@total_pages} />
      <.cover_grid :if={@items != []}>
        <%= case @live_action do %>
          <% :series -> %>
            <.series_card :for={s <- @items} series={s} />
          <% :books -> %>
            <.book_card :for={b <- @items} book={b} read={@progress_map[b.id]} />
          <% :issues -> %>
            <.book_card :for={b <- @items} book={b} read={@progress_map[b.id]} as={:issue} />
        <% end %>
      </.cover_grid>
      <.pagination page={@page} total_pages={@total_pages} scroll_to="page-top" />

      <.empty_state :if={!@loading && @items == []} ghost="0" title={"No #{String.downcase(@section)} here"} />
    </.page>
    """
  end

  @doc """
  Card for a library or a publisher: a strip of its covers, its name and its
  counts. `:menu` sits in the top-right corner, outside the link.
  """
  attr :navigate, :string, required: true
  attr :name, :string, required: true
  attr :covers, :list, default: [], doc: "cover URLs for the strip"
  attr :stats, :list, default: [], doc: "[{label, count}]; zero counts are skipped"
  attr :note, :string, default: nil, doc: "dim text shown when every count is zero"
  attr :icon, :string, default: "lucide-library"
  attr :class, :any, default: nil
  slot :menu
  slot :inner_block

  def collection_card(assigns) do
    assigns = assign(assigns, stats: Enum.filter(assigns.stats, fn {_, n} -> is_integer(n) and n > 0 end))

    ~H"""
    <div class={[
      "collection-card group relative rounded-md bg-gray-900 ring-1 ring-white/10 hover:ring-ink/60 transition-shadow",
      @class
    ]}>
      <.link navigate={@navigate} class="block rounded-md overflow-hidden focus-visible:outline-2 focus-visible:outline-ink">
        <div class="relative flex h-24 bg-gray-950 overflow-hidden">
          <div :if={@covers == []} class="flex-1 flex items-center justify-center">
            <.icon name={@icon} class="w-8 h-8 text-gray-600" />
          </div>
          <img
            :for={url <- @covers}
            src={url}
            alt=""
            loading="lazy"
            class="flex-1 min-w-0 h-full object-cover object-top"
            onerror="this.style.display='none'"
          />
          <div :if={@covers != []} class="absolute inset-0 bg-gradient-to-t from-gray-900 via-gray-900/10 to-transparent">
          </div>
        </div>
        <div class="px-3 pt-1 pb-3">
          <p class="font-display font-extrabold uppercase text-xl leading-tight tracking-wide text-white truncate group-hover:text-ink transition-colors">
            {@name}
          </p>
          <dl :if={@stats != []} class="flex flex-wrap items-baseline gap-x-3 gap-y-0.5 mt-1">
            <div :for={{label, count} <- @stats} class="flex items-baseline gap-1">
              <dd class="font-display font-bold text-base leading-none text-gray-100 tabular-nums">{count}</dd>
              <dt class="text-[10px] font-bold tracking-[0.14em] uppercase text-gray-500">{label}</dt>
            </div>
          </dl>
          <p :if={@stats == [] and @note} class="mt-1 text-xs text-gray-500">{@note}</p>
          {render_slot(@inner_block)}
        </div>
      </.link>
      <div :if={@menu != []} class="absolute top-1.5 right-1.5 rounded bg-gray-950/70 backdrop-blur-sm">
        {render_slot(@menu)}
      </div>
    </div>
    """
  end

  attr :to, :string, required: true

  defp view_all(assigns) do
    ~H"""
    <.text_link navigate={@to}>
      View all <.icon name="lucide-arrow-right" class="w-4 h-4 text-ink" />
    </.text_link>
    """
  end

  defp section_label(:series), do: "Series"
  defp section_label(:books), do: "Books"
  defp section_label(:issues), do: "Issues"

  defp overview_cover(%{recent_series: [s | _]}), do: "/api/series/#{s.id}/cover?s=s"
  defp overview_cover(%{recent_books: [b | _]}), do: "/api/books/#{b.id}/cover?s=s"
  defp overview_cover(%{recent_issues: [b | _]}), do: "/api/books/#{b.id}/cover?s=s"
  defp overview_cover(_), do: nil

  defp grid_cover(%{items: []}), do: nil
  defp grid_cover(%{live_action: :series, items: [s | _]}), do: "/api/series/#{s.id}/cover?s=s"
  defp grid_cover(%{items: [b | _]}), do: "/api/books/#{b.id}/cover?s=s"
end
