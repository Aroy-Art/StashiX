defmodule StashixWeb.SearchLive do
  use StashixWeb, :live_view

  alias Stashix.{Formatters, Library}
  alias Stashix.Library.{Book, BookCredit}

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @page_size 48
  # Per-section sample on the All tab; the grid shows 12/15/18/16 of these
  # depending on its column count (see preview_class/1).
  @preview 18

  @types [
    {"All", "all"},
    {"Issues", "issue"},
    {"Books", "standalone"},
    {"Series", "series"}
  ]

  @read_statuses [
    {"Any", ""},
    {"Unread", "unread"},
    {"In progress", "in_progress"},
    {"Read", "read"}
  ]

  @sort_options [
    {"Relevance", "relevance"},
    {"A → Z", "title_asc"},
    {"Z → A", "title_desc"},
    {"Year ↑", "year_asc"},
    {"Year ↓", "year_desc"},
    {"Date Added ↓", "added_desc"},
    {"Date Added ↑", "added_asc"}
  ]

  @age_ratings Ecto.Enum.values(Book, :age_rating)
  @age_rating_strings Enum.map(@age_ratings, &to_string/1)
  @credit_roles BookCredit |> Ecto.Enum.values(:role) |> Enum.map(&to_string/1)

  # URL params that count as filters (everything except q, type, sort, page).
  @filter_keys ~w(from to age creator creator_match role library publisher genre tag character team location status)
  # Name-based book facets, each with a typeahead picker: {param, title, plural}.
  @facets [
    {"genre", "Genre", "genres"},
    {"tag", "Tag", "tags"},
    {"character", "Character", "characters"},
    {"team", "Team", "teams"},
    {"location", "Location", "locations"}
  ]
  @facet_keys Enum.map(@facets, &elem(&1, 0))
  @max_facet_names 10
  @max_creators 10

  @impl true
  def mount(_params, _session, socket) do
    year_counts = Library.book_year_counts(socket.assigns.access)

    {:ok,
     assign(socket,
       page_title: "Search",
       params: %{},
       page: 1,
       books: [],
       books_total: 0,
       standalone_books: [],
       standalone_books_total: 0,
       series: [],
       series_total: 0,
       total_pages: 1,
       progress_map: %{},
       publishers: Library.list_publishers(socket.assigns.access),
       facets: @facets,
       # Facets nothing in the library uses stay out of the sidebar.
       facets_present: Enum.filter(@facet_keys, &Library.facet_any?(String.to_existing_atom(&1))),
       facet_query: {nil, ""},
       facet_suggestions: [],
       year_counts: year_counts,
       years: Enum.map(year_counts, &elem(&1, 0)),
       types: @types,
       read_statuses: @read_statuses,
       age_ratings: @age_ratings,
       credit_roles: @credit_roles,
       creator_query: "",
       creator_suggestions: [],
       selected_creators: [],
       navbar_sync_query: "",
       loading: true
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    params = normalize_params(params, socket.assigns.years)
    page = parse_int(params["page"]) || 1

    {:noreply,
     socket
     |> assign(params: params, page: max(page, 1), navbar_sync_query: params["q"])
     |> assign_selected_creators()
     |> load_results()}
  end

  defp assign_selected_creators(socket) do
    ids = socket.assigns.params["creator"]

    if Enum.map(socket.assigns.selected_creators, & &1.id) == ids,
      do: socket,
      else: assign(socket, selected_creators: Library.get_creators(ids))
  end

  @impl true
  # Typing in the creator box only refreshes suggestions; picking one filters.
  def handle_event("filter", %{"_target" => ["creator_search"]} = form, socket) do
    query = form["creator_search"] || ""

    {:noreply,
     assign(socket,
       creator_query: query,
       creator_suggestions:
         Library.search_creators(query,
           exclude: socket.assigns.params["creator"],
           access: socket.assigns.access
         )
     )}
  end

  # Same for the genre/tag/character/team/location boxes.
  def handle_event("filter", %{"_target" => [target]} = form, socket)
      when target in ~w(genre_search tag_search character_search team_search location_search) do
    key = String.replace_suffix(target, "_search", "")
    query = form[target] || ""

    {:noreply,
     assign(socket,
       facet_query: {key, query},
       facet_suggestions:
         Library.search_facet_names(String.to_existing_atom(key), query,
           exclude: socket.assigns.params[key],
           access: socket.assigns.access
         )
     )}
  end

  def handle_event("filter", form, socket) do
    params =
      socket.assigns.params
      |> Map.take(["type", "sort"])
      |> Map.merge(Map.take(form, ["q" | @filter_keys]))

    {:noreply, patch(socket, params, replace: true)}
  end

  # The navbar search box mirrors this page's query (see navbar_sync_query).
  def handle_event("navbar_search", %{"value" => q}, socket), do: {:noreply, set_query(socket, q)}
  def handle_event("navbar_submit", %{"q" => q}, socket), do: {:noreply, set_query(socket, q)}
  def handle_event("clear_query", _params, socket), do: {:noreply, set_query(socket, "")}

  # From the YearRange slider hook; nil means "no bound".
  def handle_event("set_years", %{"from" => from, "to" => to}, socket) do
    params = Map.merge(socket.assigns.params, %{"from" => from, "to" => to})
    {:noreply, patch(socket, params, replace: true)}
  end

  def handle_event("select_creator", %{"id" => id}, socket) do
    ids = socket.assigns.params["creator"] ++ [id]

    {:noreply,
     socket
     |> assign(creator_query: "", creator_suggestions: [])
     |> patch(Map.put(socket.assigns.params, "creator", ids))}
  end

  def handle_event("select_facet", %{"facet" => key, "name" => name}, socket) when key in @facet_keys do
    {:noreply,
     socket
     |> assign(facet_query: {nil, ""}, facet_suggestions: [])
     |> patch(Map.put(socket.assigns.params, key, socket.assigns.params[key] ++ [name]))}
  end

  # Pushed by the combobox hook, which all the pickers share.
  def handle_event("close_creator_suggestions", _params, socket) do
    {:noreply,
     assign(socket, creator_query: "", creator_suggestions: [], facet_query: {nil, ""}, facet_suggestions: [])}
  end

  def handle_event("set_type", %{"type" => type}, socket) do
    {:noreply, patch(socket, Map.put(socket.assigns.params, "type", type))}
  end

  def handle_event("sort", %{"value" => sort}, socket) do
    {:noreply, patch(socket, Map.put(socket.assigns.params, "sort", sort))}
  end

  def handle_event("remove_filter", %{"key" => key, "value" => value}, socket)
      when key in ["age", "creator" | @facet_keys] do
    values = List.delete(socket.assigns.params[key] || [], value)
    {:noreply, patch(socket, Map.put(socket.assigns.params, key, values))}
  end

  def handle_event("remove_filter", %{"key" => "year"}, socket) do
    {:noreply, patch(socket, Map.drop(socket.assigns.params, ["from", "to"]))}
  end

  def handle_event("remove_filter", %{"key" => key}, socket) do
    {:noreply, patch(socket, Map.delete(socket.assigns.params, key))}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, patch(socket, Map.drop(socket.assigns.params, @filter_keys))}
  end

  def handle_event("goto_page", %{"page" => p}, socket) do
    page = String.to_integer(p) |> max(1) |> min(socket.assigns.total_pages)
    {:noreply, push_patch(socket, to: search_path(socket.assigns.params, page))}
  end

  @impl true
  def handle_info({:scan_progress, _}, socket), do: {:noreply, socket}
  def handle_info({:book_added, _}, socket), do: {:noreply, socket}
  def handle_info({:cover_updated, _}, socket), do: {:noreply, socket}

  defp set_query(socket, q) do
    if String.trim(q) == socket.assigns.params["q"],
      do: socket,
      else: patch(socket, Map.put(socket.assigns.params, "q", q), replace: true)
  end

  # Any filter change resets pagination.
  defp patch(socket, params, opts \\ []) do
    push_patch(socket,
      to: search_path(normalize_params(params, socket.assigns.years), 1),
      replace: opts[:replace] || false
    )
  end

  defp search_path(params, page) do
    query =
      params
      |> Map.reject(fn {_k, v} -> v in [nil, "", []] end)
      |> Map.reject(fn {k, v} -> {k, v} in [{"type", "all"}, {"sort", default_sort(params)}] end)
      |> then(&if(page > 1, do: Map.put(&1, "page", page), else: &1))

    ~p"/search?#{query}"
  end

  # Keep only known, well-formed params so the URL is the single source of truth.
  # `years` are the release years present in the library; from/to must be one.
  defp normalize_params(params, years) do
    q = params |> Map.get("q", "") |> to_string() |> String.trim()

    type = if params["type"] in Enum.map(@types, &elem(&1, 1)), do: params["type"], else: "all"

    sort_values = Enum.map(@sort_options, &elem(&1, 1))
    sort = if params["sort"] in sort_values, do: params["sort"], else: nil
    # Relevance only means something with a query.
    sort = if sort == "relevance" and q == "", do: nil, else: sort

    age =
      params
      |> Map.get("age", [])
      |> List.wrap()
      |> Enum.filter(&(&1 in @age_rating_strings))
      |> Enum.uniq()

    {year_from, year_to} = normalize_year_range(params["from"], params["to"], years)

    creators =
      params
      |> Map.get("creator", [])
      |> List.wrap()
      |> Enum.map(&cast_uuid/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.take(@max_creators)

    status = if params["status"] in ["unread", "in_progress", "read"], do: params["status"]

    %{
      "q" => q,
      "type" => type,
      "sort" => sort,
      "from" => year_from,
      "to" => year_to,
      "age" => age,
      "library" => blank_to_nil(params["library"]),
      "publisher" => blank_to_nil(params["publisher"]),
      "creator" => creators,
      "creator_match" => if(length(creators) > 1 and params["creator_match"] == "any", do: "any"),
      "role" => if(params["role"] in @credit_roles, do: params["role"]),
      "status" => status,
      "page" => params["page"]
    }
    |> Map.merge(Map.new(@facet_keys, &{&1, normalize_names(params[&1])}))
    |> then(&Map.put(&1, "sort", &1["sort"] || default_sort(&1)))
  end

  # Drop years not in the library; a bound at the library's edge is no bound.
  defp normalize_year_range(_from, _to, []), do: {nil, nil}

  defp normalize_year_range(from, to, years) do
    {first, last} = {List.first(years), List.last(years)}
    valid = fn v -> (y = parse_int(v)) in years && y end
    {from, to} = {valid.(from), valid.(to)}
    {from, to} = if from && to && from > to, do: {to, from}, else: {from, to}

    {
      if(from && from != first, do: to_string(from)),
      if(to && to != last, do: to_string(to))
    }
  end

  defp default_sort(%{"q" => q}) when is_binary(q) and q != "", do: "relevance"
  defp default_sort(_), do: "title_asc"

  defp load_results(socket) do
    %{params: params, page: page} = socket.assigns
    user_id = socket.assigns.current_user.id
    filters = build_filters(params, user_id)
    offset = (page - 1) * @page_size
    access = socket.assigns.access

    {books, books_total} =
      case params["type"] do
        "series" ->
          {[], 0}

        "all" ->
          Library.search_filtered_books(Map.put(filters, :types, ["issue"]), limit: @preview, access: access)

        type ->
          Library.search_filtered_books(Map.put(filters, :types, [type]),
            limit: @page_size,
            offset: offset,
            access: access
          )
      end

    {standalone_books, standalone_books_total} =
      if params["type"] == "all" do
        Library.search_filtered_books(Map.put(filters, :types, ["standalone"]), limit: @preview, access: access)
      else
        {[], 0}
      end

    # Read status is per-book, so it can't meaningfully narrow series.
    {series, series_total} =
      cond do
        params["status"] ->
          {[], 0}

        params["type"] == "series" ->
          Library.search_filtered_series(filters, limit: @page_size, offset: offset, access: access)

        params["type"] == "all" ->
          Library.search_filtered_series(filters, limit: @preview, access: access)

        true ->
          {[], 0}
      end

    # The All tab only samples each section; paging lives on the type tabs.
    paged_total =
      case params["type"] do
        "all" -> 0
        "series" -> series_total
        _ -> books_total
      end

    assign(socket,
      books: books,
      books_total: books_total,
      standalone_books: standalone_books,
      standalone_books_total: standalone_books_total,
      series: series,
      series_total: series_total,
      total_pages: max(1, ceil(paged_total / @page_size)),
      progress_map: Library.progress_map(user_id, Enum.map(books ++ standalone_books, & &1.id)),
      loading: false
    )
  end

  defp build_filters(params, user_id) do
    %{
      q: if(String.length(params["q"]) >= 2, do: params["q"]),
      year_from: parse_int(params["from"]),
      year_to: parse_int(params["to"]),
      age_ratings: Enum.map(params["age"], &String.to_existing_atom/1),
      library_id: params["library"],
      publisher_id: params["publisher"],
      creator_ids: params["creator"],
      creator_match: params["creator_match"] || "all",
      role: params["role"],
      read_status: params["status"],
      user_id: user_id,
      sort: params["sort"]
    }
    |> Map.merge(Map.new(@facet_keys, &{String.to_existing_atom(&1), params[&1]}))
  end

  defp parse_int(nil), do: nil
  defp parse_int(v) when is_integer(v), do: v

  defp parse_int(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp cast_uuid(v) do
    case Ecto.UUID.cast(v || "") do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp blank_to_nil(v) when is_binary(v) do
    case String.trim(v) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_), do: nil

  # Chips for the active-filter bar: {label, key, value}
  defp active_filters(params, assigns) do
    year =
      case {params["from"], params["to"]} do
        {nil, nil} -> []
        {f, nil} -> [{"Released #{f}+", "year", nil}]
        {nil, t} -> [{"Released ≤ #{t}", "year", nil}]
        {y, y} -> [{"Released #{y}", "year", nil}]
        {f, t} -> [{"Released #{f}–#{t}", "year", nil}]
      end

    ages = for a <- params["age"], do: {short_age_label(a), "age", a}

    library =
      if id = params["library"] do
        name = Enum.find_value(assigns.sidebar_libraries, "Library", &(&1.id == id && &1.name))
        [{name, "library", nil}]
      else
        []
      end

    publisher =
      if id = params["publisher"] do
        name = Enum.find_value(assigns.publishers, "Publisher", &(&1.id == id && &1.name))
        [{name, "publisher", nil}]
      else
        []
      end

    joiner = if params["creator_match"] == "any", do: "or", else: "and"

    creator =
      assigns.selected_creators
      |> Enum.with_index()
      |> Enum.map(fn {c, i} ->
        label = if i == 0, do: "Creator: #{c.name}", else: "#{joiner} #{c.name}"
        {label, "creator", c.id}
      end)

    role = if r = params["role"], do: [{"Role: #{r}", "role", nil}], else: []

    status =
      if s = params["status"] do
        [{List.keyfind(@read_statuses, s, 1) |> elem(0), "status", nil}]
      else
        []
      end

    facets = for {key, title, _} <- @facets, name <- params[key], do: {"#{title}: #{name}", key, name}

    year ++ ages ++ creator ++ role ++ library ++ publisher ++ facets ++ status
  end

  # A facet param is a name or a list of names (chips on book pages link with one).
  defp normalize_names(value) do
    value
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.take(@max_facet_names)
  end

  defp short_age_label("unknown"), do: "Unrated"
  defp short_age_label("everyone"), do: "Everyone"
  defp short_age_label("teen"), do: "Teen"
  defp short_age_label("teen_plus"), do: "Teen+"
  defp short_age_label("mature"), do: "Mature"
  defp short_age_label("adult"), do: "Adult"
  defp short_age_label("explicit"), do: "Explicit"
  defp short_age_label(other), do: other

  defp filter_count(params) do
    Enum.count(@filter_keys, fn
      k when k in ["age", "creator" | @facet_keys] -> params[k] != []
      "creator_match" -> false
      k -> params[k] != nil
    end)
  end

  defp result_count(assigns) do
    case assigns.params["type"] do
      "series" -> assigns.series_total
      "all" -> assigns.books_total + assigns.standalone_books_total + assigns.series_total
      _ -> assigns.books_total
    end
  end

  # Cover of the top hit, washed across the hero like on the detail pages.
  defp backdrop_cover(%{series: [s | _]}), do: ~p"/api/series/#{s.id}/cover?s=s"

  defp backdrop_cover(assigns) do
    case Enum.find(assigns.standalone_books ++ assigns.books, & &1.cover) do
      nil -> nil
      book -> ~p"/api/books/#{book.id}/cover?s=s"
    end
  end

  defp delimit(n), do: n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")

  defp book_title(%{type: "issue", issue_number: n} = book) when not is_nil(n),
    do: "##{n} – #{book.title}"

  defp book_title(book), do: book.title

  defp book_progress(progress_map, book) do
    prog = progress_map[book.id]
    if prog && book.page_count && book.page_count > 1, do: prog / (book.page_count - 1)
  end

  defp book_subtitle(%{type: "issue", series: %{name: name}}), do: name
  defp book_subtitle(book), do: book.year && to_string(book.year)

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        active: active_filters(assigns.params, assigns),
        filter_count: filter_count(assigns.params),
        sort_options: @sort_options,
        count: result_count(assigns),
        backdrop: backdrop_cover(assigns),
        show_series: assigns.series != [] and assigns.params["type"] in ["all", "series"],
        show_standalone_books: assigns.standalone_books != [] and assigns.params["type"] == "all",
        show_books: assigns.books != []
      )

    ~H"""
    <.page wide fade cover_src={@backdrop}>
      <div class="flex flex-col gap-6 lg:grid lg:grid-cols-[minmax(0,1fr)_17rem] lg:grid-rows-[auto_auto_1fr] lg:gap-x-10 lg:gap-y-7">
        <form id="search-form" phx-change="filter" phx-submit="filter" class="contents">
          <%!-- Hero: the query is the headline, the result count looms behind it --%>
          <header class="relative lg:col-span-2 pt-2">
            <.ghost_numeral :if={@count > 0} class="hidden lg:block absolute top-1 right-0 text-[7rem] xl:text-[8rem]">
              {@count}
            </.ghost_numeral>

            <div class="rise relative flex items-center gap-3 mb-2" style="--i:1">
              <.eyebrow>Search the stash</.eyebrow>
              <span class="hidden sm:block"><.kbd keys={["Ctrl", "K"]} /></span>
            </div>

            <div class="rise relative" style="--i:2">
              <.icon
                name="lucide-search"
                class="w-7 h-7 sm:w-9 sm:h-9 md:w-10 md:h-10 absolute left-0 top-1/2 -translate-y-1/2 text-ink pointer-events-none"
              />
              <input
                id="search-q"
                type="search"
                name="q"
                value={@params["q"]}
                data-ctrl-k-target
                phx-debounce="300"
                placeholder="Title or creator"
                aria-label="Search"
                autocomplete="off"
                class="search-headline w-full pt-1 pb-2 pl-10 sm:pl-12 md:pl-14 pr-12 sm:pr-14 text-4xl sm:text-5xl md:text-6xl text-white"
                autofocus
              />
              <button
                :if={@params["q"] != ""}
                type="button"
                phx-click={JS.push("clear_query") |> JS.dispatch("stashix:clear-input", to: "#search-q")}
                aria-label="Clear search"
                class="absolute right-0 top-1/2 -translate-y-1/2 flex items-center justify-center w-9 h-9 sm:w-10 sm:h-10 rounded-full bg-gray-800 hover:bg-ink text-gray-200 hover:text-gray-950 transition-colors"
              >
                <.icon name="lucide-x" class="w-5 h-5" />
              </button>
            </div>

            <p
              class="rise relative flex items-center flex-wrap gap-x-3 gap-y-1 mt-4 text-sm text-gray-300 tabular-nums"
              style="--i:3"
            >
              <span>
                <span class="text-white font-semibold">{delimit(@count)}</span>
                {if @count == 1, do: "result", else: "results"}
              </span>
              <%= if @params["type"] == "all" do %>
                <span :if={@series_total > 0}>{delimit(@series_total)} series</span>
                <span :if={@standalone_books_total > 0}>
                  {delimit(@standalone_books_total)} {if @standalone_books_total == 1, do: "book", else: "books"}
                </span>
                <span :if={@books_total > 0}>
                  {delimit(@books_total)} {if @books_total == 1, do: "issue", else: "issues"}
                </span>
              <% end %>
            </p>
          </header>

          <%!-- Filters: rail on lg+, slide-over drawer below --%>
          <aside
            id="search-filters"
            aria-label="Filters"
            class="filter-drawer lg:col-start-2 lg:row-start-2 lg:row-span-2 lg:self-start"
          >
            <.panel
              variant="rail"
              class="min-h-full lg:min-h-0 lg:rounded-lg"
              inner_class="lg:rounded-lg lg:ring-1 lg:ring-white/10 divide-y divide-gray-800"
            >
              <div class="sticky top-0 z-10 flex items-center gap-3 px-5 py-4 bg-gray-900 lg:static lg:bg-transparent">
                <.display_heading size="panel" count={@filter_count > 0 && @filter_count} count_tone="ink">
                  Filters
                </.display_heading>
                <.text_link :if={@filter_count > 0} type="button" phx-click="clear_filters" class="ml-auto">
                  Clear all
                </.text_link>
                <button
                  type="button"
                  phx-click={close_filters()}
                  aria-label="Close filters"
                  class={[
                    "lg:hidden flex items-center justify-center w-8 h-8 rounded-lg bg-gray-800 hover:bg-gray-700 text-gray-300 hover:text-white transition-colors",
                    @filter_count == 0 && "ml-auto"
                  ]}
                >
                  <.icon name="lucide-x" class="w-4 h-4" />
                </button>
              </div>

              <.filter_section :if={@year_counts != []} title="Release year">
                <.year_range counts={@year_counts} from={@params["from"]} to={@params["to"]} />
              </.filter_section>

              <.filter_section title="Age rating">
                <div class="flex flex-wrap gap-1.5">
                  <%= for rating <- @age_ratings do %>
                    <% value = to_string(rating) %>
                    <.pill active={value in @params["age"]}>
                      <input
                        type="checkbox"
                        name="age[]"
                        value={value}
                        checked={value in @params["age"]}
                        class="sr-only"
                      />
                      <span title={Formatters.format_age_rating(rating)}>{short_age_label(value)}</span>
                    </.pill>
                  <% end %>
                </div>
              </.filter_section>

              <.filter_section title="Read status">
                <div class="grid grid-cols-2 gap-1.5">
                  <%= for {label, value} <- @read_statuses do %>
                    <.pill active={(@params["status"] || "") == value} class="text-center">
                      <input
                        type="radio"
                        name="status"
                        value={value}
                        checked={(@params["status"] || "") == value}
                        class="sr-only"
                      />
                      {label}
                    </.pill>
                  <% end %>
                </div>
              </.filter_section>

              <.filter_section title="Creator">
                <.creator_picker
                  selected={@selected_creators}
                  match={@params["creator_match"] || "all"}
                  query={@creator_query}
                  suggestions={@creator_suggestions}
                />
                <.ink_select
                  id="filter-role"
                  name="role"
                  label="Role"
                  variant="field"
                  prompt="Any role"
                  value={@params["role"]}
                  options={Enum.map(@credit_roles, &{&1, &1})}
                />
              </.filter_section>

              <.filter_section :if={length(@sidebar_libraries) > 1} title="Library">
                <.ink_select
                  id="filter-library"
                  name="library"
                  label="Library"
                  variant="field"
                  prompt="All libraries"
                  value={@params["library"]}
                  options={Enum.map(@sidebar_libraries, &{&1.name, &1.id})}
                />
              </.filter_section>

              <.filter_section :if={@publishers != []} title="Publisher">
                <.ink_select
                  id="filter-publisher"
                  name="publisher"
                  label="Publisher"
                  variant="field"
                  prompt="All publishers"
                  searchable
                  value={@params["publisher"]}
                  options={Enum.map(@publishers, &{&1.name, &1.id})}
                />
              </.filter_section>

              <.filter_section
                :for={{key, title, plural} <- @facets}
                :if={key in @facets_present || @params[key] != []}
                title={title}
              >
                <.facet_picker
                  key={key}
                  plural={plural}
                  selected={@params[key]}
                  query={if elem(@facet_query, 0) == key, do: elem(@facet_query, 1), else: ""}
                  suggestions={@facet_suggestions}
                />
              </.filter_section>

              <div class="lg:hidden sticky bottom-0 px-5 py-4 bg-gray-900">
                <.ink_button type="button" phx-click={close_filters()} class="w-full">
                  Show {delimit(@count)} {if @count == 1, do: "result", else: "results"}
                </.ink_button>
              </div>
            </.panel>
          </aside>
        </form>

        <div
          id="search-filters-backdrop"
          phx-click={close_filters()}
          phx-window-keydown={close_filters()}
          phx-key="Escape"
          class="hidden lg:hidden fixed inset-0 z-40 bg-black/70"
          aria-hidden="true"
        >
        </div>

        <%!-- Type tabs, filter toggle and sort --%>
        <div class="lg:col-start-1 lg:row-start-2 min-w-0 flex flex-wrap items-center justify-between gap-x-4 gap-y-4 pb-4 border-b border-white/15">
          <div class="flex items-center gap-1 sm:gap-2" role="tablist" aria-label="Result type">
            <%= for {label, value} <- @types do %>
              <button
                type="button"
                role="tab"
                aria-selected={to_string(@params["type"] == value)}
                phx-click="set_type"
                phx-value-type={value}
                class={[
                  "px-2.5 sm:px-3 pt-1 pb-0.5 font-display font-black uppercase text-2xl sm:text-3xl leading-none rounded-sm transition-colors",
                  if(@params["type"] == value,
                    do: "bg-ink text-gray-950 -rotate-2",
                    else: "text-gray-300 hover:text-white hover:bg-white/10"
                  )
                ]}
              >
                {label}
              </button>
            <% end %>
          </div>
          <div class="flex w-full sm:w-auto items-center gap-2">
            <button
              type="button"
              phx-click={open_filters()}
              class="lg:hidden inline-flex items-center gap-2 h-9 px-4 text-sm font-medium rounded-full border bg-gray-900 border-gray-600 text-gray-100 hover:border-gray-400 transition-colors"
            >
              <.icon name="lucide-sliders-horizontal" class="w-3.5 h-3.5" /> Filters
              <span
                :if={@filter_count > 0}
                class="px-1.5 rounded-sm bg-ink text-gray-950 text-xs font-bold tabular-nums"
              >
                {@filter_count}
              </span>
            </button>
            <form id="search-sort" phx-change="sort" class="ml-auto">
              <.ink_select
                id="search-sort-input"
                name="value"
                label="Sort results"
                value={@params["sort"]}
                options={Enum.filter(@sort_options, fn {_, value} -> value != "relevance" or @params["q"] != "" end)}
              />
            </form>
          </div>
        </div>

        <%!-- Results --%>
        <div class="lg:col-start-1 lg:row-start-3 space-y-8 min-w-0">
          <div :if={@active != []} class="flex flex-wrap items-center gap-2">
            <%= for {label, key, value} <- @active do %>
              <button
                type="button"
                phx-click="remove_filter"
                phx-value-key={key}
                phx-value-value={value}
                class="inline-flex items-center gap-1.5 pl-2.5 pr-1.5 py-1 text-xs font-semibold rounded-sm bg-gray-900 border border-ink/70 text-ink hover:bg-ink hover:text-gray-950 transition-colors"
              >
                {label}
                <.icon name="lucide-x" class="w-3 h-3" />
              </button>
            <% end %>
            <.text_link type="button" phx-click="clear_filters" class="px-1">Clear all</.text_link>
          </div>

          <section :if={@show_series}>
            <.results_heading
              title="Series"
              total={@series_total}
              show_all={@params["type"] == "all" and @series_total > 12 and "series"}
            />
            <.cover_grid id={if @params["type"] == "series", do: "page-top"}>
              <.series_card
                :for={{s, i} <- Enum.with_index(@series)}
                series={s}
                class={if @params["type"] == "all", do: preview_class(i)}
              />
            </.cover_grid>
            <.show_more :if={@params["type"] == "all"} total={@series_total} type="series" one="series" many="series" />
          </section>

          <section :if={@show_standalone_books}>
            <.results_heading
              title="Books"
              total={@standalone_books_total}
              show_all={@standalone_books_total > 12 and "standalone"}
            />
            <.cover_grid>
              <.media_card
                :for={{b, i} <- Enum.with_index(@standalone_books)}
                class={preview_class(i)}
                navigate={~p"/book/#{b.id}"}
                title={book_title(b)}
                cover_url={b.cover && ~p"/api/books/#{b.id}/cover"}
                size="m"
                subtitle={book_subtitle(b)}
                progress={book_progress(@progress_map, b)}
                page_count={b.page_count}
                type={:book}
                blurhash={b.cover && b.cover.blurhash}
              />
            </.cover_grid>
            <.show_more total={@standalone_books_total} type="standalone" one="book" many="books" />
          </section>

          <section :if={@show_books}>
            <.results_heading
              :if={@params["type"] == "all"}
              title="Issues"
              total={@books_total}
              show_all={@books_total > 12 and "issue"}
            />
            <.cover_grid id="page-top">
              <.media_card
                :for={{book, i} <- Enum.with_index(@books)}
                class={if @params["type"] == "all", do: preview_class(i)}
                navigate={~p"/book/#{book.id}"}
                title={book_title(book)}
                cover_url={book.cover && ~p"/api/books/#{book.id}/cover"}
                size="m"
                subtitle={book_subtitle(book)}
                progress={book_progress(@progress_map, book)}
                page_count={book.page_count}
                type={:book}
                blurhash={book.cover && book.cover.blurhash}
              />
            </.cover_grid>
            <.show_more :if={@params["type"] == "all"} total={@books_total} type="issue" one="issue" many="issues" />
          </section>

          <.pagination page={@page} total_pages={@total_pages} scroll_to="page-top" />

          <%!-- Empty long box --%>
          <.empty_state
            :if={!@loading and !@show_series and !@show_standalone_books and !@show_books}
            ghost="0"
            title={if @filter_count > 0 or @params["q"] != "", do: "Nothing in the long box", else: "Nothing here yet"}
          >
            <span :if={@filter_count > 0 or @params["q"] != ""}>Loosen the filters or try another spelling.</span>
            <:actions :if={@filter_count > 0}>
              <.ink_button type="button" phx-click="clear_filters">
                <.icon name="lucide-filter-x" class="w-4 h-4" /> Clear filters
              </.ink_button>
            </:actions>
          </.empty_state>
        </div>
      </div>
    </.page>
    """
  end

  # The filter drawer below lg; on lg+ the same element is a rail and these do nothing visible.
  defp open_filters do
    JS.add_class("is-open", to: "#search-filters")
    |> JS.remove_class("hidden", to: "#search-filters-backdrop")
  end

  defp close_filters do
    JS.remove_class("is-open", to: "#search-filters")
    |> JS.add_class("hidden", to: "#search-filters-backdrop")
  end

  # The All tab previews whole rows only. The grid is 3/4/5/6/8 columns wide,
  # so each section shows 12 below md, 15 on md, 18 on xl and 16 on 2xl.
  defp preview_class(i) when i >= 16, do: "hidden xl:block 2xl:hidden"
  defp preview_class(15), do: "hidden xl:block"
  defp preview_class(i) when i >= 12, do: "hidden md:block"
  defp preview_class(_), do: nil

  attr :title, :string, required: true
  attr :total, :integer, required: true
  attr :show_all, :any, default: false, doc: "type to switch to, or false"

  defp results_heading(assigns) do
    ~H"""
    <div class="flex items-end justify-between gap-4 mb-4">
      <.display_heading count={delimit(@total)}>{@title}</.display_heading>
      <.text_link :if={@show_all} type="button" phx-click="set_type" phx-value-type={@show_all}>
        Show all <.icon name="lucide-arrow-right" class="w-4 h-4 text-ink" />
      </.text_link>
    </div>
    """
  end

  attr :total, :integer, required: true
  attr :type, :string, required: true
  attr :one, :string, required: true
  attr :many, :string, required: true

  # "Show N more" under a preview grid. How many cards are visible depends on
  # the column count (see preview_class/1), so each breakpoint gets its own
  # button with the matching remainder.
  defp show_more(assigns) do
    ~H"""
    <button
      :for={
        {shown, visible} <- [
          {12, "flex md:hidden"},
          {15, "hidden md:flex xl:hidden"},
          {18, "hidden xl:flex 2xl:hidden"},
          {16, "hidden 2xl:flex"}
        ]
      }
      :if={@total > shown}
      type="button"
      phx-click="set_type"
      phx-value-type={@type}
      class={[
        visible,
        "group items-center justify-center gap-2.5 w-full mt-4 px-5 py-3 rounded-md border border-gray-600 bg-gray-900 text-white font-display font-extrabold uppercase text-xl leading-none tracking-wide hover:border-ink hover:bg-gray-800 transition-colors"
      ]}
    >
      Show <span class="text-ink tabular-nums">{delimit(@total - shown)}</span>
      more {if @total - shown == 1, do: @one, else: @many}
      <.icon name="lucide-arrow-right" class="w-4 h-4 text-ink transition-transform group-hover:translate-x-1" />
    </button>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp filter_section(assigns) do
    ~H"""
    <div class="px-5 py-4 space-y-2.5">
      <.eyebrow tag="h3" tone="light">{@title}</.eyebrow>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :counts, :list, required: true
  attr :from, :string, default: nil
  attr :to, :string, default: nil

  # Histogram of books per year with a two-handle slider underneath. Bars and
  # handles share one linear axis (first..last year); the YearRange hook snaps
  # handles to years that have books and pushes "set_years" on release.
  defp year_range(assigns) do
    {first, _} = List.first(assigns.counts)
    {last, _} = List.last(assigns.counts)
    by_year = Map.new(assigns.counts)
    peak = assigns.counts |> Enum.map(&elem(&1, 1)) |> Enum.max()
    lo = if assigns.from, do: String.to_integer(assigns.from), else: first
    hi = if assigns.to, do: String.to_integer(assigns.to), else: last
    span = max(last - first, 1)

    bars =
      for year <- first..last do
        count = Map.get(by_year, year, 0)

        %{
          year: year,
          count: count,
          # keep tiny counts visible next to much bigger years
          height: if(count > 0, do: max(count / peak * 100, 4), else: 0),
          left: (year - first) / span * 100,
          active: count > 0 and year >= lo and year <= hi
        }
      end

    assigns =
      assign(assigns,
        first: first,
        last: last,
        lo: lo,
        hi: hi,
        bars: bars,
        bar_width: 100 / (last - first + 1),
        span: span,
        total: Enum.sum(for b <- bars, b.active, do: b.count)
      )

    ~H"""
    <div
      id="year-range"
      phx-hook="YearRange"
      data-years={Jason.encode!(Enum.map(@counts, &elem(&1, 0)))}
      data-counts={Jason.encode!(Map.new(@counts))}
      data-min={@first}
      data-max={@last}
      class="space-y-1.5"
    >
      <div class="flex items-baseline justify-between">
        <span
          data-label
          class="font-display font-bold uppercase text-xl leading-tight tracking-wide text-white tabular-nums"
        >
          {if @lo == @first and @hi == @last, do: "Any year", else: "#{@lo} – #{@hi}"}
        </span>
        <span data-total class="text-xs text-gray-400 tabular-nums">{@total} books</span>
      </div>

      <%!-- Inset by half a thumb so bar centres line up with handle centres --%>
      <div class="relative h-14 mx-[7px]">
        <div
          :for={b <- @bars}
          data-bar
          data-year={b.year}
          data-active={b.active}
          title={"#{b.year}: #{b.count} #{if b.count == 1, do: "book", else: "books"}"}
          class="absolute bottom-0 -translate-x-1/2 rounded-t-[1px] bg-gray-600 data-[active]:bg-violet-500 transition-colors"
          style={"left: #{b.left}%; width: max(#{@bar_width}%, 1px); height: #{b.height}%;"}
        />
      </div>

      <div class="relative h-4">
        <div class="absolute inset-x-[7px] top-1/2 -translate-y-1/2 h-1 rounded-full bg-gray-800">
          <div
            data-track
            class="absolute inset-y-0 rounded-full bg-violet-500"
            style={"left: #{(@lo - @first) / @span * 100}%; right: #{(@last - @hi) / @span * 100}%;"}
          />
        </div>
        <input
          type="range"
          data-thumb="lo"
          min={@first}
          max={@last}
          value={@lo}
          aria-label="From year"
          class="year-range-input absolute inset-0 w-full"
        />
        <input
          type="range"
          data-thumb="hi"
          min={@first}
          max={@last}
          value={@hi}
          aria-label="To year"
          class="year-range-input absolute inset-0 w-full"
        />
      </div>

      <div class="flex justify-between text-[10px] text-gray-400 tabular-nums">
        <span>{@first}</span>
        <span>{@last}</span>
      </div>

      <%!-- Carry the range along when other filters change --%>
      <input type="hidden" name="from" value={@from} />
      <input type="hidden" name="to" value={@to} />
    </div>
    """
  end

  attr :selected, :list, required: true
  attr :match, :string, required: true
  attr :query, :string, required: true
  attr :suggestions, :list, required: true

  defp creator_picker(assigns) do
    assigns = assign(assigns, :full, length(assigns.selected) >= @max_creators)

    ~H"""
    <div :if={@selected != []} class="flex flex-wrap gap-1.5">
      <.picked :for={c <- @selected} name="creator[]" key="creator" value={c.id} label={c.name} />
    </div>

    <div
      :if={length(@selected) > 1}
      class="grid grid-cols-2 gap-1.5"
      title="Match books credited to all selected creators, or to any of them"
    >
      <.pill
        :for={{label, value} <- [{"All of them", "all"}, {"Any of them", "any"}]}
        active={@match == value}
        class="text-center"
      >
        <input
          type="radio"
          name="creator_match"
          value={value}
          checked={@match == value}
          class="sr-only"
        />
        {label}
      </.pill>
    </div>

    <div :if={!@full} id="creator-picker" phx-hook="CreatorCombobox" class="relative">
      <input
        id="creator-search"
        type="text"
        name="creator_search"
        value={@query}
        placeholder={if @selected == [], do: "Search creators...", else: "Add another creator..."}
        autocomplete="off"
        role="combobox"
        aria-autocomplete="list"
        aria-controls="creator-options"
        aria-expanded={to_string(@query != "")}
        phx-debounce="200"
        class={field_class()}
      />
      <div :if={@query != ""} id="creator-options" role="listbox" class={listbox_class()}>
        <button
          :for={c <- @suggestions}
          type="button"
          role="option"
          data-option
          phx-click="select_creator"
          phx-value-id={c.id}
          class={option_class()}
        >
          <span class="truncate">{c.name}</span>
          <span class="shrink-0 text-xs text-gray-400 tabular-nums">{c.credits}</span>
        </button>
        <div :if={@suggestions == []} class="px-3 py-2.5 text-sm text-gray-400">
          No creators found
        </div>
      </div>
    </div>
    """
  end

  attr :key, :string, required: true
  attr :plural, :string, required: true
  attr :selected, :list, required: true
  attr :query, :string, required: true
  attr :suggestions, :list, required: true

  # Typeahead for a name-based facet; same interaction as the creator picker.
  defp facet_picker(assigns) do
    assigns = assign(assigns, :full, length(assigns.selected) >= @max_facet_names)

    ~H"""
    <div :if={@selected != []} class="flex flex-wrap gap-1.5">
      <.picked :for={name <- @selected} name={"#{@key}[]"} key={@key} value={name} label={name} />
    </div>

    <div :if={!@full} id={"#{@key}-picker"} phx-hook="CreatorCombobox" class="relative">
      <input
        id={"#{@key}-search"}
        type="text"
        name={"#{@key}_search"}
        value={@query}
        placeholder={if @selected == [], do: "Search #{@plural}...", else: "Add another..."}
        autocomplete="off"
        role="combobox"
        aria-autocomplete="list"
        aria-controls={"#{@key}-options"}
        aria-expanded={to_string(@query != "")}
        phx-debounce="200"
        class={field_class()}
      />
      <div :if={@query != ""} id={"#{@key}-options"} role="listbox" class={listbox_class()}>
        <button
          :for={s <- @suggestions}
          type="button"
          role="option"
          data-option
          phx-click="select_facet"
          phx-value-facet={@key}
          phx-value-name={s.name}
          class={option_class()}
        >
          <span class="truncate">{s.name}</span>
          <span class="shrink-0 text-xs text-gray-400 tabular-nums">{s.books}</span>
        </button>
        <div :if={@suggestions == []} class="px-3 py-2.5 text-sm text-gray-400">
          No {@plural} found
        </div>
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :key, :string, required: true
  attr :value, :string, required: true
  attr :label, :string, required: true

  # A picked creator/facet value: carries the value in the form, removable.
  defp picked(assigns) do
    ~H"""
    <span class="inline-flex max-w-full items-center gap-1 pl-2.5 pr-1 py-0.5 rounded-sm bg-gray-950 border border-ink/70 text-xs font-semibold text-ink">
      <input type="hidden" name={@name} value={@value} />
      <span class="truncate">{@label}</span>
      <button
        type="button"
        phx-click="remove_filter"
        phx-value-key={@key}
        phx-value-value={@value}
        aria-label={"Remove #{@label}"}
        class="p-0.5 rounded-sm hover:bg-ink hover:text-gray-950 transition-colors"
      >
        <.icon name="lucide-x" class="w-3.5 h-3.5" />
      </button>
    </span>
    """
  end

  defp field_class,
    do:
      "w-full bg-gray-800 border border-gray-600 rounded-md px-2.5 py-1.5 text-sm text-white placeholder-gray-400 hover:border-gray-400 focus:outline-none focus:border-ink transition-colors"

  defp listbox_class,
    do:
      "absolute z-30 top-full left-0 right-0 mt-1 max-h-72 overflow-y-auto bg-gray-800 border border-gray-700 rounded-lg shadow-2xl"

  defp option_class,
    do:
      "w-full flex items-center justify-between gap-2 px-3 py-2 text-left text-sm text-gray-300 hover:bg-gray-700 hover:text-white data-[active]:bg-ink data-[active]:text-gray-950"
end
