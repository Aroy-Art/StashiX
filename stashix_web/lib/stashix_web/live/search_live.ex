defmodule StashixWeb.SearchLive do
  use StashixWeb, :live_view

  alias Stashix.{Formatters, Library}
  alias Stashix.Library.{Book, BookCredit}

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @page_size 48
  @series_preview 12

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
  @filter_keys ~w(from to age creator creator_match role library publisher genre status)
  @max_creators 10

  @impl true
  def mount(_params, _session, socket) do
    {year_min, year_max} = Library.search_year_bounds()

    {:ok,
     assign(socket,
       page_title: "Search",
       params: %{},
       page: 1,
       books: [],
       books_total: 0,
       series: [],
       series_total: 0,
       total_pages: 1,
       progress_map: %{},
       publishers: Library.list_publishers(),
       genres: Library.list_genre_names(),
       year_min: year_min,
       year_max: year_max,
       types: @types,
       read_statuses: @read_statuses,
       age_ratings: @age_ratings,
       credit_roles: @credit_roles,
       creator_query: "",
       creator_suggestions: [],
       selected_creators: [],
       loading: true
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    params = normalize_params(params)
    page = parse_int(params["page"]) || 1

    {:noreply,
     socket
     |> assign(params: params, page: max(page, 1))
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
       creator_suggestions: Library.search_creators(query, exclude: socket.assigns.params["creator"])
     )}
  end

  def handle_event("filter", form, socket) do
    params =
      socket.assigns.params
      |> Map.take(["type", "sort"])
      |> Map.merge(Map.take(form, ["q" | @filter_keys]))

    {:noreply, patch(socket, params, replace: true)}
  end

  def handle_event("select_creator", %{"id" => id}, socket) do
    ids = socket.assigns.params["creator"] ++ [id]

    {:noreply,
     socket
     |> assign(creator_query: "", creator_suggestions: [])
     |> patch(Map.put(socket.assigns.params, "creator", ids))}
  end

  def handle_event("close_creator_suggestions", _params, socket) do
    {:noreply, assign(socket, creator_query: "", creator_suggestions: [])}
  end

  def handle_event("set_type", %{"type" => type}, socket) do
    {:noreply, patch(socket, Map.put(socket.assigns.params, "type", type))}
  end

  def handle_event("sort", %{"value" => sort}, socket) do
    {:noreply, patch(socket, Map.put(socket.assigns.params, "sort", sort))}
  end

  def handle_event("remove_filter", %{"key" => key, "value" => value}, socket)
      when key in ["age", "creator"] do
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

  # Any filter change resets pagination.
  defp patch(socket, params, opts \\ []) do
    push_patch(socket, to: search_path(normalize_params(params), 1), replace: opts[:replace] || false)
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
  defp normalize_params(params) do
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
      "from" => params["from"] |> parse_int() |> maybe_to_string(),
      "to" => params["to"] |> parse_int() |> maybe_to_string(),
      "age" => age,
      "library" => blank_to_nil(params["library"]),
      "publisher" => blank_to_nil(params["publisher"]),
      "genre" => blank_to_nil(params["genre"]),
      "creator" => creators,
      "creator_match" => if(length(creators) > 1 and params["creator_match"] == "any", do: "any"),
      "role" => if(params["role"] in @credit_roles, do: params["role"]),
      "status" => status,
      "page" => params["page"]
    }
    |> then(&Map.put(&1, "sort", &1["sort"] || default_sort(&1)))
  end

  defp default_sort(%{"q" => q}) when is_binary(q) and q != "", do: "relevance"
  defp default_sort(_), do: "title_asc"

  defp load_results(socket) do
    %{params: params, page: page} = socket.assigns
    user_id = socket.assigns.current_user.id
    filters = build_filters(params, user_id)
    offset = (page - 1) * @page_size

    {books, books_total} =
      case params["type"] do
        "series" ->
          {[], 0}

        "all" ->
          Library.search_filtered_books(Map.put(filters, :types, ["issue", "standalone"]),
            limit: @page_size,
            offset: offset
          )

        type ->
          Library.search_filtered_books(Map.put(filters, :types, [type]),
            limit: @page_size,
            offset: offset
          )
      end

    # Read status is per-book, so it can't meaningfully narrow series.
    {series, series_total} =
      cond do
        params["status"] -> {[], 0}
        params["type"] == "series" -> Library.search_filtered_series(filters, limit: @page_size, offset: offset)
        params["type"] == "all" and page == 1 -> Library.search_filtered_series(filters, limit: @series_preview)
        true -> {[], 0}
      end

    paged_total = if params["type"] == "series", do: series_total, else: books_total

    assign(socket,
      books: books,
      books_total: books_total,
      series: series,
      series_total: series_total,
      total_pages: max(1, ceil(paged_total / @page_size)),
      progress_map: Library.progress_map(user_id, Enum.map(books, & &1.id)),
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
      genre: params["genre"],
      creator_ids: params["creator"],
      creator_match: params["creator_match"] || "all",
      role: params["role"],
      read_status: params["status"],
      user_id: user_id,
      sort: params["sort"]
    }
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

  defp maybe_to_string(nil), do: nil
  defp maybe_to_string(n), do: to_string(n)

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

    genre = if g = params["genre"], do: [{g, "genre", nil}], else: []

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

    year ++ ages ++ creator ++ role ++ library ++ publisher ++ genre ++ status
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
      k when k in ["age", "creator"] -> params[k] != []
      "creator_match" -> false
      k -> params[k] != nil
    end)
  end

  defp results_summary(assigns) do
    count =
      case assigns.params["type"] do
        "series" -> assigns.series_total
        "all" -> assigns.books_total + assigns.series_total
        _ -> assigns.books_total
      end

    noun = if count == 1, do: "result", else: "results"

    if assigns.params["q"] != "",
      do: "#{count} #{noun} for “#{assigns.params["q"]}”",
      else: "#{count} #{noun}"
  end

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
        show_series: assigns.series != [] and assigns.params["type"] in ["all", "series"],
        show_books: assigns.books != []
      )

    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-2xl font-bold text-white">Search</h1>
        <p class="text-sm text-gray-500 mt-0.5">{results_summary(assigns)}</p>
      </div>

      <div class="flex flex-col gap-6 lg:grid lg:grid-cols-[16rem_minmax(0,1fr)] lg:grid-rows-[auto_auto_1fr] lg:gap-x-8">
        <form id="search-form" phx-change="filter" phx-submit="filter" class="contents">
          <%!-- Search input spans the full width --%>
          <div class="relative order-1 lg:order-none lg:col-span-2">
            <.icon
              name="lucide-search"
              class="w-5 h-5 absolute left-4 top-1/2 -translate-y-1/2 text-gray-500 pointer-events-none"
            />
            <input
              type="search"
              name="q"
              value={@params["q"]}
              phx-debounce="300"
              placeholder="Search books, series, creators..."
              autocomplete="off"
              class="w-full bg-gray-900 border border-gray-700 rounded-xl pl-12 pr-4 py-3 text-white placeholder-gray-500 focus:outline-none focus:border-violet-500 text-lg"
              autofocus
            />
          </div>

          <%!-- Filter sidebar --%>
          <aside
            id="search-filters"
            class="hidden order-3 lg:order-none lg:block lg:col-start-1 lg:row-start-2 lg:row-span-2 lg:self-start lg:sticky lg:top-4"
          >
            <div class="bg-gray-900 border border-gray-800 rounded-xl divide-y divide-gray-800">
              <div class="flex items-center justify-between px-4 py-3">
                <h2 class="text-sm font-semibold text-white">Filters</h2>
                <button
                  :if={@filter_count > 0}
                  type="button"
                  phx-click="clear_filters"
                  class="text-xs text-gray-400 hover:text-white"
                >
                  Clear all
                </button>
              </div>

              <.filter_section title="Release year">
                <div class="flex items-center gap-2">
                  <input
                    type="number"
                    name="from"
                    value={@params["from"]}
                    placeholder={@year_min && to_string(@year_min)}
                    min="1800"
                    max="2100"
                    phx-debounce="500"
                    class="w-full min-w-0 bg-gray-800 border border-gray-700 rounded-lg px-2.5 py-1.5 text-sm text-white placeholder-gray-600 focus:outline-none focus:border-violet-500"
                  />
                  <span class="text-gray-600">–</span>
                  <input
                    type="number"
                    name="to"
                    value={@params["to"]}
                    placeholder={@year_max && to_string(@year_max)}
                    min="1800"
                    max="2100"
                    phx-debounce="500"
                    class="w-full min-w-0 bg-gray-800 border border-gray-700 rounded-lg px-2.5 py-1.5 text-sm text-white placeholder-gray-600 focus:outline-none focus:border-violet-500"
                  />
                </div>
              </.filter_section>

              <.filter_section title="Age rating">
                <div class="flex flex-wrap gap-1.5">
                  <%= for rating <- @age_ratings do %>
                    <% value = to_string(rating) %>
                    <label class={[
                      "cursor-pointer select-none px-2.5 py-1 text-xs rounded-lg border transition-colors",
                      if(value in @params["age"],
                        do: "bg-violet-600 border-violet-500 text-white",
                        else: "bg-gray-800 border-gray-700 text-gray-400 hover:text-white"
                      )
                    ]}>
                      <input
                        type="checkbox"
                        name="age[]"
                        value={value}
                        checked={value in @params["age"]}
                        class="sr-only"
                      />
                      <span title={Formatters.format_age_rating(rating)}>{short_age_label(value)}</span>
                    </label>
                  <% end %>
                </div>
              </.filter_section>

              <.filter_section title="Read status">
                <div class="grid grid-cols-2 gap-1.5">
                  <%= for {label, value} <- @read_statuses do %>
                    <label class={[
                      "cursor-pointer select-none text-center px-2 py-1 text-xs rounded-lg border transition-colors",
                      if((@params["status"] || "") == value,
                        do: "bg-violet-600 border-violet-500 text-white",
                        else: "bg-gray-800 border-gray-700 text-gray-400 hover:text-white"
                      )
                    ]}>
                      <input
                        type="radio"
                        name="status"
                        value={value}
                        checked={(@params["status"] || "") == value}
                        class="sr-only"
                      />
                      {label}
                    </label>
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
                <.filter_select name="role" selected={@params["role"]} prompt="Any role">
                  <option :for={r <- @credit_roles} value={r} selected={@params["role"] == r}>
                    {r}
                  </option>
                </.filter_select>
              </.filter_section>

              <.filter_section :if={length(@sidebar_libraries) > 1} title="Library">
                <.filter_select name="library" selected={@params["library"]} prompt="All libraries">
                  <option :for={lib <- @sidebar_libraries} value={lib.id} selected={@params["library"] == lib.id}>
                    {lib.name}
                  </option>
                </.filter_select>
              </.filter_section>

              <.filter_section :if={@publishers != []} title="Publisher">
                <.filter_select name="publisher" selected={@params["publisher"]} prompt="All publishers">
                  <option :for={p <- @publishers} value={p.id} selected={@params["publisher"] == p.id}>
                    {p.name}
                  </option>
                </.filter_select>
              </.filter_section>

              <.filter_section :if={@genres != []} title="Genre">
                <.filter_select name="genre" selected={@params["genre"]} prompt="All genres">
                  <option :for={g <- @genres} value={g} selected={@params["genre"] == g}>{g}</option>
                </.filter_select>
              </.filter_section>
            </div>
          </aside>
        </form>

        <%!-- Type tabs, filter toggle and sort --%>
        <div class="order-2 lg:order-none lg:col-start-2 lg:row-start-2 min-w-0 flex flex-wrap items-center justify-between gap-x-3 gap-y-6">
          <div class="flex w-full sm:w-auto items-center gap-1 p-1 bg-gray-900 border border-gray-800 rounded-xl">
            <%= for {label, value} <- @types do %>
              <button
                type="button"
                phx-click="set_type"
                phx-value-type={value}
                class={[
                  "flex-1 sm:flex-none px-3 py-1 text-sm rounded-lg transition-colors",
                  if(@params["type"] == value,
                    do: "bg-gray-100 text-gray-900 font-semibold",
                    else: "text-gray-400 hover:text-white"
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
              phx-click={JS.toggle_class("hidden", to: "#search-filters")}
              class="lg:hidden inline-flex items-center gap-2 h-8 px-3 text-sm rounded-lg border bg-gray-800 border-gray-700 text-gray-300 hover:text-white"
            >
              <.icon name="lucide-sliders-horizontal" class="w-4 h-4" /> Filters
              <span
                :if={@filter_count > 0}
                class="px-1.5 rounded-full bg-violet-600 text-white text-xs font-semibold"
              >
                {@filter_count}
              </span>
            </button>
            <.sort_select
              class="ml-auto"
              select_class="h-8"
              options={
                if @params["q"] == "",
                  do: Enum.reject(@sort_options, &(elem(&1, 1) == "relevance")),
                  else: @sort_options
              }
              selected={@params["sort"]}
            />
          </div>
        </div>

        <%!-- Results --%>
        <div class="order-4 lg:order-none lg:col-start-2 lg:row-start-3 space-y-6 min-w-0">
          <div :if={@active != []} class="flex flex-wrap items-center gap-2">
            <%= for {label, key, value} <- @active do %>
              <button
                type="button"
                phx-click="remove_filter"
                phx-value-key={key}
                phx-value-value={value}
                class="inline-flex items-center gap-1.5 pl-3 pr-2 py-1 text-xs rounded-full bg-violet-600/20 border border-violet-500/40 text-violet-200 hover:bg-violet-600/30"
              >
                {label}
                <.icon name="lucide-x" class="w-3 h-3" />
              </button>
            <% end %>
            <button
              type="button"
              phx-click="clear_filters"
              class="text-xs text-gray-500 hover:text-white px-1"
            >
              Clear all
            </button>
          </div>

          <section :if={@show_series} class="space-y-3">
            <div class="flex items-center justify-between">
              <h2 class="text-sm font-semibold uppercase tracking-widest text-gray-400">
                Series <span class="text-gray-600 font-normal">{@series_total}</span>
              </h2>
              <button
                :if={@params["type"] == "all" and @series_total > length(@series)}
                type="button"
                phx-click="set_type"
                phx-value-type="series"
                class="text-xs text-violet-400 hover:text-violet-300"
              >
                Show all →
              </button>
            </div>
            <.media_grid id={if @params["type"] == "series", do: "page-top"}>
              <.media_card
                :for={{s, i} <- Enum.with_index(@series)}
                class={if @params["type"] == "all" and i >= 6, do: "hidden sm:block"}
                navigate={~p"/series/#{s.id}"}
                title={s.name}
                cover_url={~p"/api/series/#{s.id}/cover"}
                size="m"
                subtitle={s.start_year && to_string(s.start_year)}
                badge={"#{s.issue_count} issues"}
                type={:series}
                blurhash={s.cover_blurhash}
              />
            </.media_grid>
          </section>

          <section :if={@show_books} class="space-y-3">
            <h2
              :if={@params["type"] == "all"}
              class="text-sm font-semibold uppercase tracking-widest text-gray-400"
            >
              Books &amp; Issues <span class="text-gray-600 font-normal">{@books_total}</span>
            </h2>
            <.media_grid id="page-top">
              <.media_card
                :for={book <- @books}
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
            </.media_grid>
          </section>

          <.pagination page={@page} total_pages={@total_pages} scroll_to="page-top" />

          <.browse_empty
            :if={!@loading and !@show_series and !@show_books}
            icon="lucide-search-x"
            label={
              if @filter_count > 0 or @params["q"] != "",
                do: "Nothing matches these filters.",
                else: "Nothing here yet."
            }
          />
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp filter_section(assigns) do
    ~H"""
    <div class="px-4 py-3 space-y-2">
      <h3 class="text-xs font-semibold uppercase tracking-wider text-gray-500">{@title}</h3>
      {render_slot(@inner_block)}
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
      <span
        :for={c <- @selected}
        class="inline-flex max-w-full items-center gap-1 pl-2.5 pr-1 py-0.5 bg-violet-600/20 border border-violet-500/40 rounded-lg text-sm text-violet-100"
      >
        <input type="hidden" name="creator[]" value={c.id} />
        <span class="truncate">{c.name}</span>
        <button
          type="button"
          phx-click="remove_filter"
          phx-value-key="creator"
          phx-value-value={c.id}
          aria-label={"Remove #{c.name}"}
          class="p-0.5 rounded-md text-violet-300 hover:text-white hover:bg-violet-600/40"
        >
          <.icon name="lucide-x" class="w-3.5 h-3.5" />
        </button>
      </span>
    </div>

    <div
      :if={length(@selected) > 1}
      class="grid grid-cols-2 gap-1.5"
      title="Match books credited to all selected creators, or to any of them"
    >
      <label
        :for={{label, value} <- [{"All of them", "all"}, {"Any of them", "any"}]}
        class={[
          "cursor-pointer select-none text-center px-2 py-1 text-xs rounded-lg border transition-colors",
          if(@match == value,
            do: "bg-violet-600 border-violet-500 text-white",
            else: "bg-gray-800 border-gray-700 text-gray-400 hover:text-white"
          )
        ]}
      >
        <input
          type="radio"
          name="creator_match"
          value={value}
          checked={@match == value}
          class="sr-only"
        />
        {label}
      </label>
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
        class="w-full bg-gray-800 border border-gray-700 rounded-lg px-2.5 py-1.5 text-sm text-white placeholder-gray-600 focus:outline-none focus:border-violet-500"
      />
      <div
        :if={@query != ""}
        id="creator-options"
        role="listbox"
        class="absolute z-30 top-full left-0 right-0 mt-1 max-h-72 overflow-y-auto bg-gray-800 border border-gray-700 rounded-lg shadow-xl"
      >
        <button
          :for={c <- @suggestions}
          type="button"
          role="option"
          data-option
          phx-click="select_creator"
          phx-value-id={c.id}
          class="w-full flex items-center justify-between gap-2 px-3 py-2 text-left text-sm text-gray-300 hover:bg-gray-700 hover:text-white data-[active]:bg-gray-700 data-[active]:text-white"
        >
          <span class="truncate">{c.name}</span>
          <span class="shrink-0 text-xs text-gray-500">{c.credits}</span>
        </button>
        <div :if={@suggestions == []} class="px-3 py-2.5 text-sm text-gray-500">
          No creators found
        </div>
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :selected, :string, default: nil
  attr :prompt, :string, required: true
  slot :inner_block, required: true

  defp filter_select(assigns) do
    ~H"""
    <select
      name={@name}
      class="w-full bg-gray-800 border border-gray-700 rounded-lg px-2.5 py-1.5 text-sm text-white focus:outline-none focus:border-violet-500 cursor-pointer"
    >
      <option value="" selected={is_nil(@selected)}>{@prompt}</option>
      {render_slot(@inner_block)}
    </select>
    """
  end
end
