# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.CreatorLive do
  @moduledoc """
  A creator's work, one tab per role heading (written, art, covers…). Each tab
  shows a shelf of the series, books and issues they worked on in that role,
  and each shelf opens a paginated grid (`?kind=`).
  """
  use StashixWeb, :live_view

  import StashixWeb.CollectionComponents, only: [view_all: 1]

  alias Stashix.{Formatters, Library}

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @page_size 48
  @shelf_size 20

  # {heading, url slug, tab label}
  @tabs [
    {"Writer", "written", "Written"},
    {"Artist", "art", "Art"},
    {"Colorist", "colors", "Colors"},
    {"Letterer", "letters", "Letters"},
    {"Cover", "covers", "Covers"},
    {"Editor", "edited", "Edited"},
    {"Translator", "translated", "Translated"},
    {"Other", "other", "Other"}
  ]

  # Headings a creator is rarely looked up for; the page opens on another tab when it can.
  @secondary ~w(Cover Editor Other)

  # {kind, url slug, heading}
  @kinds [{:series, "series", "Series"}, {:books, "books", "Books"}, {:issues, "issues", "Issues"}]

  @series_sort_options [
    {"Most issues", "count_desc"},
    {"A → Z", "title_asc"},
    {"Z → A", "title_desc"},
    {"Year ↑", "year_asc"},
    {"Year ↓", "year_desc"}
  ]

  @book_sort_options [
    {"Year ↑", "year_asc"},
    {"Year ↓", "year_desc"},
    {"A → Z", "title_asc"},
    {"Z → A", "title_desc"}
  ]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    creator = Library.get_creator!(id)
    works = Library.creator_works(socket.assigns.access, creator.id)

    tabs =
      for {heading, slug, label} <- @tabs, list = works.groups[heading], list != [] do
        %{heading: heading, slug: slug, label: label, count: Enum.sum(Enum.map(list, & &1.count))}
      end

    {:ok, assign(socket, page_title: creator.name, creator: creator, works: works, tabs: tabs)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tabs = socket.assigns.tabs
    tab = Enum.find(tabs, &(&1.slug == params["role"])) || default_tab(tabs)
    lists = if tab, do: kind_lists(socket.assigns.works, tab.heading), else: %{}

    kind =
      Enum.find_value(@kinds, fn {kind, slug, _} ->
        if slug == params["kind"] and lists[kind] != [], do: kind
      end)

    socket = assign(socket, tab: tab, kind: kind)

    {:noreply, if(kind, do: assign_grid(socket, lists[kind], params), else: assign_shelves(socket, lists))}
  end

  @impl true
  def handle_event("sort", %{"value" => sort}, socket) do
    {:noreply, push_patch(socket, to: grid_path(socket, page: 1, sort: sort))}
  end

  def handle_event("goto_page", %{"page" => p}, socket) do
    {:noreply, push_patch(socket, to: grid_path(socket, page: parse_page(p)))}
  end

  @impl true
  def handle_info({:cover_updated, _}, socket), do: {:noreply, socket}
  def handle_info({:scan_progress, _}, socket), do: {:noreply, socket}
  def handle_info({:book_added, _}, socket), do: {:noreply, socket}

  defp default_tab([]), do: nil

  defp default_tab(tabs) do
    case Enum.reject(tabs, &(&1.heading in @secondary)) do
      [] -> Enum.max_by(tabs, & &1.count)
      primary -> Enum.max_by(primary, & &1.count)
    end
  end

  # The tab's series (works inside a series), standalone books, and issues.
  defp kind_lists(works, heading) do
    {books, issues} = Enum.split_with(works.book_groups[heading] || [], &(&1.type == "standalone"))

    %{
      series: Enum.filter(works.groups[heading] || [], & &1.series_id),
      books: books,
      issues: issues
    }
  end

  defp assign_shelves(socket, lists) do
    access = socket.assigns.access

    shelves =
      for {kind, slug, title} <- @kinds, list = lists[kind] || [], list != [] do
        entries = list |> sort_entries(kind, default_sort(kind)) |> Enum.take(@shelf_size)
        %{kind: kind, slug: slug, title: title, count: length(list), items: load_items(access, kind, entries)}
      end

    assign(socket, shelves: shelves, items: [])
  end

  defp assign_grid(socket, list, params) do
    kind = socket.assigns.kind
    options = sort_options(kind)
    sort = if params["sort"] in Enum.map(options, &elem(&1, 1)), do: params["sort"], else: default_sort(kind)
    total_pages = max(1, ceil(length(list) / @page_size))
    page = params["page"] |> parse_page() |> min(total_pages)
    entries = list |> sort_entries(kind, sort) |> Enum.slice((page - 1) * @page_size, @page_size)

    assign(socket,
      shelves: [],
      total: length(list),
      sort: sort,
      sort_options: options,
      page: page,
      total_pages: total_pages,
      items: load_items(socket.assigns.access, kind, entries)
    )
  end

  defp sort_options(:series), do: @series_sort_options
  defp sort_options(_kind), do: @book_sort_options

  defp default_sort(:series), do: "count_desc"
  defp default_sort(_kind), do: "year_asc"

  defp sort_entries(works, :series, "title_asc"), do: Enum.sort_by(works, &String.downcase(&1.name || ""))
  defp sort_entries(works, :series, "title_desc"), do: Enum.sort_by(works, &String.downcase(&1.name || ""), :desc)

  defp sort_entries(works, :series, "year_asc"),
    do: Enum.sort_by(works, &{is_nil(&1.first_year), &1.first_year, &1.name})

  defp sort_entries(works, :series, "year_desc"),
    do: Enum.sort_by(works, &{is_nil(&1.first_year), -(&1.first_year || 0), &1.name})

  defp sort_entries(works, :series, _count_desc), do: Enum.sort_by(works, &{-&1.count, &1.name})

  defp sort_entries(books, _kind, "title_asc"), do: Enum.sort_by(books, &book_name/1)
  defp sort_entries(books, _kind, "title_desc"), do: Enum.sort_by(books, &book_name/1, :desc)

  defp sort_entries(books, _kind, "year_desc"),
    do: Enum.sort_by(books, &{is_nil(&1.year), -(&1.year || 0), book_name(&1)})

  defp sort_entries(books, _kind, _year_asc), do: Enum.sort_by(books, &{is_nil(&1.year), &1.year, book_name(&1)})

  # Issues sort by series then number, books by title.
  defp book_name(%{series_name: series, issue_number: n, title: title}) when is_binary(series),
    do: {String.downcase(series), issue_sort(n), String.downcase(title || "")}

  defp book_name(%{title: title}), do: {String.downcase(title || ""), 0, ""}

  defp issue_sort(nil), do: :infinity
  defp issue_sort(n), do: Decimal.to_float(n)

  # Pairs each entry with its series or book in the entries' order, dropping any that vanished since mount.
  defp load_items(access, :series, works) do
    by_id = access |> Library.list_series_by_ids(Enum.map(works, & &1.series_id)) |> Map.new(&{&1.id, &1})
    for w <- works, s = by_id[w.series_id], do: {s, w}
  end

  defp load_items(access, _kind, books) do
    by_id = access |> Library.list_books_by_ids(Enum.map(books, & &1.id)) |> Map.new(&{&1.id, &1})
    for entry <- books, b = by_id[entry.id], do: {b, entry}
  end

  defp parse_page(p) do
    case Integer.parse(to_string(p || "1")) do
      {n, _} when n > 0 -> n
      _ -> 1
    end
  end

  defp kind_slug(kind), do: Enum.find_value(@kinds, fn {k, slug, _} -> if k == kind, do: slug end)
  defp kind_title(kind), do: Enum.find_value(@kinds, fn {k, _, title} -> if k == kind, do: title end)

  defp grid_path(socket, overrides) do
    a = socket.assigns

    params =
      %{role: a.tab.slug, kind: kind_slug(a.kind), sort: a.sort, page: a.page}
      |> Map.merge(Map.new(overrides))

    ~p"/creator/#{a.creator.id}?#{params}"
  end

  defp years(%{first_year: first, last_year: last}),
    do: Formatters.series_years(%{start_year: first, end_year: last, ongoing: false})

  # Detailed roles ("Penciller, Inker") when they say more than the tab does.
  defp role_detail(roles, heading) do
    names = roles |> Enum.map(&to_string/1) |> Enum.sort()
    if Enum.all?(names, &(&1 in [heading, "Cover Artist"])), do: nil, else: Enum.join(names, ", ")
  end

  defp join_parts(parts) do
    case Enum.reject(parts, &is_nil/1) do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  defp series_subtitle(work, heading), do: join_parts([years(work), role_detail(work.roles, heading)])

  defp book_subtitle(:issues, entry, heading),
    do: join_parts([entry.series_name || (entry.year && to_string(entry.year)), role_detail(entry.roles, heading)])

  defp book_subtitle(_books, entry, heading),
    do: join_parts([entry.year && to_string(entry.year), role_detail(entry.roles, heading)])

  defp issues(1), do: "1 issue"
  defp issues(n), do: "#{n} issues"

  defp cover_src(%{shelves: [%{kind: kind, items: items} | _]}), do: item_cover(kind, items)
  defp cover_src(%{kind: kind, items: items}) when not is_nil(kind), do: item_cover(kind, items)
  defp cover_src(_assigns), do: nil

  defp item_cover(:series, [{s, _} | _]), do: "/api/series/#{s.id}/cover?s=s"
  defp item_cover(_kind, [{b, _} | _]), do: "/api/books/#{b.id}/cover?s=s"
  defp item_cover(_kind, _items), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <.page wide fade cover_src={cover_src(assigns)}>
      <.crumbs crumbs={[{"Home", "/"}, {@creator.name, nil}]} />

      <.page_hero title={@creator.name} eyebrow="Creator">
        <:meta>
          <span :if={@works.books > 0}>
            <span class="text-fg font-semibold">{@works.books}</span>
            {if @works.books == 1, do: "book", else: "books"}
          </span>
          <span :if={years(@works)}>{years(@works)}</span>
          <.text_link navigate={~p"/search?#{%{creator: [@creator.id]}}"}>Filter in search</.text_link>
        </:meta>
      </.page_hero>

      <%= if @tab do %>
        <.tabs label="Roles">
          <:tab
            :for={t <- @tabs}
            patch={~p"/creator/#{@creator.id}?#{%{role: t.slug}}"}
            active={t.slug == @tab.slug}
            count={t.count}
          >
            {t.label}
          </:tab>
        </.tabs>

        <%= if @kind do %>
          <div class="flex flex-wrap items-end justify-between gap-x-4 gap-y-2">
            <.display_heading count={@total}>{kind_title(@kind)}</.display_heading>
            <.text_link patch={~p"/creator/#{@creator.id}?#{%{role: @tab.slug}}"}>
              <.icon name="lucide-arrow-left" class="w-4 h-4 text-ink" /> All {String.downcase(@tab.label)}
            </.text_link>
          </div>

          <.browse_toolbar sort_options={@sort_options} sort={@sort} />

          <.pagination id="page-top" page={@page} total_pages={@total_pages} />
          <.cover_grid>
            <%= for {record, entry} <- @items do %>
              <.series_card
                :if={@kind == :series}
                series={record}
                badge={issues(entry.count)}
                subtitle={series_subtitle(entry, @tab.heading)}
              />
              <.book_card
                :if={@kind != :series}
                book={record}
                as={if @kind == :issues, do: :issue, else: :book}
                subtitle={book_subtitle(@kind, entry, @tab.heading)}
              />
            <% end %>
          </.cover_grid>
          <.pagination page={@page} total_pages={@total_pages} scroll_to="page-top" />
        <% else %>
          <.shelf :for={s <- @shelves} id={"creator-#{s.slug}"} title={s.title} count={s.count}>
            <:actions>
              <.view_all to={~p"/creator/#{@creator.id}?#{%{role: @tab.slug, kind: s.slug}}"} />
            </:actions>
            <%= for {record, entry} <- s.items do %>
              <.series_card
                :if={s.kind == :series}
                series={record}
                badge={issues(entry.count)}
                subtitle={series_subtitle(entry, @tab.heading)}
                class="flex-shrink-0 w-36"
              />
              <.book_card
                :if={s.kind != :series}
                book={record}
                as={if s.kind == :issues, do: :issue, else: :book}
                subtitle={book_subtitle(s.kind, entry, @tab.heading)}
                class="flex-shrink-0 w-36"
              />
            <% end %>
          </.shelf>
        <% end %>
      <% else %>
        <.empty_state ghost="0" title="No books by this creator">
          None of their credits are on books you can see.
        </.empty_state>
      <% end %>
    </.page>
    """
  end
end
