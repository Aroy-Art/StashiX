# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.CreatorLive do
  @moduledoc """
  A creator's work, one tab per role heading (written, art, covers…), each a
  grid of the series they worked on with how many issues and which years.
  """
  use StashixWeb, :live_view

  alias Stashix.{Formatters, Library}

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @page_size 48

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

  @sort_options [
    {"Most issues", "count_desc"},
    {"A → Z", "title_asc"},
    {"Z → A", "title_desc"},
    {"Year ↑", "year_asc"},
    {"Year ↓", "year_desc"}
  ]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    creator = Library.get_creator!(id)
    works = Library.creator_works(socket.assigns.access, creator.id)

    tabs =
      for {heading, slug, label} <- @tabs, list = works.groups[heading], list != [] do
        %{heading: heading, slug: slug, label: label, count: Enum.sum(Enum.map(list, & &1.count))}
      end

    {:ok,
     assign(socket,
       page_title: creator.name,
       creator: creator,
       works: works,
       tabs: tabs,
       sort_options: @sort_options
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tabs = socket.assigns.tabs
    tab = Enum.find(tabs, &(&1.slug == params["role"])) || default_tab(tabs)
    sort = if params["sort"] in Enum.map(@sort_options, &elem(&1, 1)), do: params["sort"], else: "count_desc"
    works = if tab, do: sort_works(socket.assigns.works.groups[tab.heading], sort), else: []
    total_pages = max(1, ceil(length(works) / @page_size))
    page = params["page"] |> parse_page() |> min(total_pages)

    {:noreply,
     assign(socket,
       tab: tab,
       sort: sort,
       page: page,
       total_pages: total_pages,
       items: load_items(socket.assigns.access, Enum.slice(works, (page - 1) * @page_size, @page_size))
     )}
  end

  @impl true
  def handle_event("sort", %{"value" => sort}, socket) do
    {:noreply, push_patch(socket, to: tab_path(socket, page: 1, sort: sort))}
  end

  def handle_event("goto_page", %{"page" => p}, socket) do
    {:noreply, push_patch(socket, to: tab_path(socket, page: parse_page(p)))}
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

  defp sort_works(works, "title_asc"), do: Enum.sort_by(works, &String.downcase(&1.name || ""))
  defp sort_works(works, "title_desc"), do: Enum.sort_by(works, &String.downcase(&1.name || ""), :desc)
  defp sort_works(works, "year_asc"), do: Enum.sort_by(works, &{is_nil(&1.first_year), &1.first_year, &1.name})

  defp sort_works(works, "year_desc"),
    do: Enum.sort_by(works, &{is_nil(&1.first_year), -(&1.first_year || 0), &1.name})

  defp sort_works(works, _count_desc), do: Enum.sort_by(works, &{-&1.count, &1.name})

  # Pairs each work on the page with its series or book, dropping any that vanished since mount.
  defp load_items(access, works) do
    series =
      access |> Library.list_series_by_ids(for(w <- works, w.series_id, do: w.series_id)) |> Map.new(&{&1.id, &1})

    books = access |> Library.list_books_by_ids(for(w <- works, w.book_id, do: w.book_id)) |> Map.new(&{&1.id, &1})

    Enum.flat_map(works, fn w ->
      cond do
        s = w.series_id && series[w.series_id] -> [{:series, s, w}]
        b = w.book_id && books[w.book_id] -> [{:book, b, w}]
        true -> []
      end
    end)
  end

  defp parse_page(p) do
    case Integer.parse(to_string(p || "1")) do
      {n, _} when n > 0 -> n
      _ -> 1
    end
  end

  defp tab_path(socket, overrides) do
    params =
      %{role: socket.assigns.tab && socket.assigns.tab.slug, sort: socket.assigns.sort, page: socket.assigns.page}
      |> Map.merge(Map.new(overrides))

    ~p"/creator/#{socket.assigns.creator.id}?#{params}"
  end

  defp years(%{first_year: first, last_year: last}),
    do: Formatters.series_years(%{start_year: first, end_year: last, ongoing: false})

  # Detailed roles ("Penciller, Inker") when they say more than the tab does.
  defp role_detail(roles, heading) do
    names = roles |> Enum.map(&to_string/1) |> Enum.sort()
    if Enum.all?(names, &(&1 in [heading, "Cover Artist"])), do: nil, else: Enum.join(names, ", ")
  end

  defp subtitle(work, heading) do
    case Enum.reject([years(work), role_detail(work.roles, heading)], &is_nil/1) do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  defp issues(1), do: "1 issue"
  defp issues(n), do: "#{n} issues"

  defp cover_src([{:series, s, _} | _]), do: "/api/series/#{s.id}/cover?s=s"
  defp cover_src([{:book, b, _} | _]), do: "/api/books/#{b.id}/cover?s=s"
  defp cover_src(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <.page wide fade cover_src={cover_src(@items)}>
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
            patch={~p"/creator/#{@creator.id}?#{%{role: t.slug, sort: @sort}}"}
            active={t.slug == @tab.slug}
            count={t.count}
          >
            {t.label}
          </:tab>
        </.tabs>

        <.browse_toolbar sort_options={@sort_options} sort={@sort} />

        <.pagination id="page-top" page={@page} total_pages={@total_pages} />
        <.cover_grid>
          <%= for item <- @items do %>
            <%= case item do %>
              <% {:series, s, w} -> %>
                <.series_card series={s} badge={issues(w.count)} subtitle={subtitle(w, @tab.heading)} />
              <% {:book, b, w} -> %>
                <.book_card book={b} subtitle={subtitle(w, @tab.heading)} />
            <% end %>
          <% end %>
        </.cover_grid>
        <.pagination page={@page} total_pages={@total_pages} scroll_to="page-top" />
      <% else %>
        <.empty_state ghost="0" title="No books by this creator">
          None of their credits are on books you can see.
        </.empty_state>
      <% end %>
    </.page>
    """
  end
end
