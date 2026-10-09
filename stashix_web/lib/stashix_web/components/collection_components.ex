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
        <:actions><.view_all to={"#{@base_path}/series"} /></:actions>
        <.series_card :for={s <- @recent_series} series={s} class="flex-shrink-0 w-36" />
      </.shelf>

      <.shelf :if={@recent_books != []} id="collection-books" title="Books" count={@books_count}>
        <:actions><.view_all to={"#{@base_path}/books"} /></:actions>
        <.book_card :for={b <- @recent_books} book={b} class="flex-shrink-0 w-36" />
      </.shelf>

      <.shelf :if={@recent_issues != []} id="collection-issues" title="Issues" count={@issues_count}>
        <:actions><.view_all to={"#{@base_path}/issues"} /></:actions>
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
  Card for a library or a publisher: a plain panel with an ink left edge and
  halftone dots, a strip of its covers, its name and its counts under ink
  labels. `:menu` sits in the
  top-right corner, outside the link; the default slot is a line below the
  counts.
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
    <%!-- A plain panel with the ink left edge and the halftone dots of an
         indicia, without its colour wash, and a strip of covers across the top. --%>
    <div class={[
      "collection-card group relative overflow-hidden rounded-lg bg-gray-900 border-l-4 border-ink ring-1 ring-white/10 hover:ring-ink/60 transition-shadow",
      @class
    ]}>
      <div class="halftone absolute inset-0 pointer-events-none" aria-hidden="true"></div>
      <.link navigate={@navigate} class="absolute inset-0 focus-visible:outline-2 focus-visible:outline-ink z-0">
        <span class="sr-only">{@name}</span>
      </.link>
      <div class="relative pointer-events-none">
        <div class="relative flex h-24 bg-gray-950 overflow-hidden border-b border-white/10">
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
          <div :if={@covers != []} class="absolute inset-x-0 bottom-0 h-10 bg-gradient-to-t from-gray-950/80 to-transparent">
          </div>
        </div>
        <div class="px-4 pt-3 pb-4">
          <div class="flex items-start justify-between gap-2">
            <p class="font-display font-black uppercase text-2xl leading-none tracking-wide text-white truncate group-hover:text-ink transition-colors">
              {@name}
            </p>
            <div
              :if={@menu != []}
              class="pointer-events-auto flex-shrink-0 -mt-0.5 -mr-1.5 rounded-full bg-white/5 ring-1 ring-white/10 [box-shadow:0_0_8px_5px_rgb(3_7_18/0.9)] transition-opacity md:opacity-0 md:group-hover:opacity-100"
            >
              {render_slot(@menu)}
            </div>
          </div>
          <dl :if={@stats != []} class="flex flex-wrap gap-x-6 gap-y-2 mt-3">
            <.stat :for={{label, count} <- @stats} label={label}>{count}</.stat>
          </dl>
          <p :if={@stats == [] and @note} class="mt-2 text-xs text-gray-400">{@note}</p>
          <div :if={@inner_block != []} class="pointer-events-auto mt-2.5">{render_slot(@inner_block)}</div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Publisher-specific card: narrow cover-spine strip on the left, name + stats on the right.
  """
  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :name, :string, required: true
  attr :covers, :list, default: [], doc: "[{url, blurhash}] pairs"
  attr :stats, :list, default: []

  def publisher_card(assigns) do
    assigns = assign(assigns, stats: Enum.filter(assigns.stats, fn {_, n} -> is_integer(n) and n > 0 end))

    ~H"""
    <div class="group relative overflow-hidden rounded-lg bg-gray-900 ring-1 ring-white/10 hover:ring-ink/40 transition-all duration-200">
      <div class="halftone absolute inset-0 pointer-events-none" aria-hidden="true"></div>
      <.link navigate={@navigate} class="relative flex h-36 focus-visible:outline-2 focus-visible:outline-ink">
        <div class="relative w-24 flex-shrink-0 overflow-hidden bg-gray-950">
          <div :if={@covers == []} class="flex h-full items-center justify-center">
            <.icon name="lucide-building" class="w-6 h-6 text-gray-700" />
          </div>
          <div :if={@covers != []} class="flex flex-col h-full">
            <div
              :for={{{url, blurhash}, i} <- Enum.with_index(@covers)}
              class="relative flex-1 min-h-0 overflow-hidden"
            >
              <.blurhash_image
                id={"#{@id}-c#{i}"}
                src={url}
                blurhash={blurhash}
                class="absolute inset-0 w-full h-full object-cover object-left"
              />
            </div>
          </div>
          <div class="absolute inset-y-0 right-0 w-6 bg-gradient-to-r from-transparent to-gray-900/80 pointer-events-none">
          </div>
        </div>
        <div class="flex-1 min-w-0 flex flex-col justify-center px-4 py-5 border-l border-white/5">
          <p class="font-display font-black uppercase leading-tight tracking-wide text-white group-hover:text-ink transition-colors line-clamp-2 text-lg">
            {@name}
          </p>
          <dl :if={@stats != []} class="flex flex-col gap-0.5 mt-2.5">
            <div :for={{label, count} <- @stats} class="flex items-baseline gap-2">
              <span class="text-sm font-bold text-white tabular-nums">{count}</span>
              <span class="text-[10px] uppercase tracking-widest text-ink/80 font-semibold">{label}</span>
            </div>
          </dl>
          <p :if={@stats == []} class="mt-1 text-xs text-gray-500">No content</p>
        </div>
      </.link>
    </div>
    """
  end

  attr :to, :string, required: true

  def view_all(assigns) do
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
