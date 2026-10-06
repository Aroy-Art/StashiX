defmodule StashixWeb.IdentifyComponent do
  @moduledoc """
  "Identify" dialog: search a metadata source for a book (issue) or series,
  preview a result against the current data, choose which fields to write and
  apply it.

  The parent LiveView renders it while its identify dialog is open and handles
  `"close_identify_dialog"` plus `{:identify_applied, kind, id}` messages.
  Pass `review` to start from a stored review's query and candidates.

  The modal is plain server-rendered markup (no JS dialog hook) so it does not
  re-animate when its content changes.
  """
  use StashixWeb, :live_component

  alias Stashix.{Metadata, Repo}
  alias Stashix.Metadata.{Apply, Candidate, Importer, Matcher, Sources}
  alias Stashix.Library.{Book, Series}

  @impl true
  # Sent from the search/preview task when the source's rate limiter makes it wait.
  # Sub-second spacing waits aren't worth a notice.
  def update(%{rate_wait: {ms, _limit}}, socket) when ms < 2_000, do: {:ok, socket}

  def update(%{rate_wait: {ms, limit}}, socket) do
    ticking? = socket.assigns.wait_until != nil
    socket = assign(socket, wait_until: System.monotonic_time(:millisecond) + ms, wait_limit: limit)
    {:ok, if(ticking?, do: socket, else: schedule_wait_tick(socket))}
  end

  def update(%{wait_tick: true}, socket), do: {:ok, schedule_wait_tick(socket)}

  def update(assigns, socket) do
    first_mount? = not Map.has_key?(socket.assigns, :kind)
    socket = assign(socket, assigns)
    # The parent re-sends its own copy of the target whenever it reloads it.
    socket = assign(socket, target: preload_target(socket.assigns.target))

    if first_mount? do
      {:ok, init(socket)}
    else
      {:ok, socket}
    end
  end

  defp preload_target(%Book{} = book), do: Repo.preload(book, [:files, :library])
  defp preload_target(other), do: other

  defp init(socket) do
    target = socket.assigns.target
    kind = if match?(%Series{}, target), do: :series, else: :issue
    review = socket.assigns[:review]

    sources =
      Sources.enabled()
      |> Enum.filter(&Sources.configured?(&1.module, &1.config.config))
      |> Enum.map(&{&1.module.key(), &1.module.name()})

    query =
      cond do
        review && review.query != %{} -> review.query
        kind == :series -> Matcher.series_query(target)
        true -> Matcher.book_query(target)
      end

    candidates = if review, do: Metadata.review_candidates(review), else: []
    known_ids = known_ids(target, Enum.map(sources, &elem(&1, 0)))

    socket =
      socket
      |> assign(
        target: target,
        kind: kind,
        sources: sources,
        known_ids: known_ids,
        linked_lookup: nil,
        wait_until: nil,
        wait_limit: nil,
        source_key: (List.first(candidates) && List.first(candidates).source_key) || first_key(sources),
        form: to_form(stringify(query), as: :q),
        refresh: false,
        candidates: candidates,
        selected: nil,
        preview: nil,
        rows: [],
        selected_fields: MapSet.new(),
        error: review && review.error,
        searching: false,
        loading_preview: false,
        applying: false,
        queue_issues: true
      )

    # A stored source id beats searching: fetch it straight away. Search stays
    # available for when the linked entry is wrong.
    case {review, Enum.find(sources, fn {k, _} -> Map.has_key?(known_ids, k) end)} do
      {nil, {key, _}} -> lookup_known(socket, key)
      _ -> socket
    end
  end

  # %{source_key => source_id} for usable sources the target already has an id for.
  defp known_ids(target, source_keys) do
    stored = target |> Repo.preload(:external_ids, force: true) |> Map.get(:external_ids)

    for source <- Sources.enabled(),
        source.module.key() in source_keys,
        id = Enum.find_value(stored, &(to_string(&1.source) == source.module.information_source() && &1.source_id)),
        into: %{},
        do: {source.module.key(), id}
  end

  defp lookup_known(socket, source_key) do
    id = Map.fetch!(socket.assigns.known_ids, source_key)
    kind = socket.assigns.kind
    candidate = %Candidate{source_key: source_key, kind: kind, id: id, score: 1.0}
    opts = [refresh: socket.assigns.refresh]

    socket
    |> assign(source_key: source_key, candidates: [candidate], error: nil, linked_lookup: {source_key, id})
    |> assign(selected: candidate, preview: nil, rows: [], loading_preview: true)
    |> start_async(
      :preview,
      report_waits(socket, fn ->
        if kind == :series,
          do: Metadata.fetch_series(source_key, id, opts),
          else: Metadata.fetch_issue(source_key, id, opts)
      end)
    )
  end

  defp linked?(known_ids, %Candidate{source_key: key, id: id}), do: Map.get(known_ids, key) == to_string(id)

  # A candidate built from a bare id has nothing to show until its record loads.
  defp enrich_candidate(%Candidate{series_name: nil} = c, m) do
    %{
      c
      | series_name: m[:series] || m[:name],
        number: Matcher.format_number(m[:issue_number]),
        title: m[:title],
        year: m[:year] || m[:start_year],
        publisher: m[:publisher],
        cover_url: m[:cover_url],
        issue_count: m[:issue_count]
    }
  end

  defp enrich_candidate(c, _m), do: c

  # Re-renders once a second while a rate-limit wait is shown.
  defp schedule_wait_tick(socket) do
    if wait_remaining(socket.assigns.wait_until) > 0 do
      send_update_after(self(), __MODULE__, [id: socket.assigns.id, wait_tick: true], 1_000)
      socket
    else
      assign(socket, wait_until: nil)
    end
  end

  defp wait_remaining(nil), do: 0
  defp wait_remaining(until), do: max(0, until - System.monotonic_time(:millisecond))

  # Runs `fun` in the async task, reporting rate-limit waits back to this component.
  defp report_waits(socket, fun) do
    lv = self()
    id = socket.assigns.id

    fn ->
      Stashix.Metadata.RateLimiter.on_wait(&send_update(lv, __MODULE__, id: id, rate_wait: {&1, &2}))
      fun.()
    end
  end

  defp first_key([{k, _} | _]), do: k
  defp first_key(_), do: nil

  defp stringify(query),
    do: Map.new(query, fn {k, v} -> {to_string(k), if(is_nil(v), do: "", else: to_string(v))} end)

  # ── Events ──────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("search", %{"q" => q} = params, socket) do
    source_key = params["source"] || socket.assigns.source_key
    refresh = params["refresh"] == "true"
    kind = socket.assigns.kind

    query = %{
      "series_name" => String.trim(q["series_name"] || ""),
      "number" => blank_to_nil(q["number"]),
      "year" => int(q["year"]),
      "series_year" => int(q["year"]),
      "publisher" => blank_to_nil(q["publisher"])
    }

    socket =
      socket
      |> assign(source_key: source_key, refresh: refresh, form: to_form(q, as: :q), searching: true, error: nil)
      |> assign(linked_lookup: nil)
      |> assign(selected: nil, preview: nil, rows: [])
      |> start_async(
        :search,
        report_waits(socket, fn ->
          Metadata.search(source_key, if(kind == :series, do: :series, else: :issue), query, refresh: refresh)
        end)
      )

    {:noreply, socket}
  end

  def handle_event("lookup_known", %{"source" => key}, socket) do
    if Map.has_key?(socket.assigns.known_ids, key),
      do: {:noreply, lookup_known(socket, key)},
      else: {:noreply, socket}
  end

  def handle_event("select", %{"idx" => idx}, socket) do
    candidate = Enum.at(socket.assigns.candidates, String.to_integer(idx))
    kind = socket.assigns.kind
    opts = [refresh: socket.assigns.refresh]

    socket =
      socket
      |> assign(selected: candidate, preview: nil, rows: [], loading_preview: true, error: nil)
      |> assign(linked_lookup: if(linked?(socket.assigns.known_ids, candidate), do: socket.assigns.linked_lookup))
      |> start_async(
        :preview,
        report_waits(socket, fn ->
          if kind == :series,
            do: Metadata.fetch_series(candidate.source_key, candidate.id, opts),
            else: Metadata.fetch_issue(candidate.source_key, candidate.id, opts)
        end)
      )

    {:noreply, socket}
  end

  def handle_event("toggle_field", %{"field" => field}, socket) do
    selected = socket.assigns.selected_fields

    selected =
      if MapSet.member?(selected, field),
        do: MapSet.delete(selected, field),
        else: MapSet.put(selected, field)

    {:noreply, assign(socket, selected_fields: selected)}
  end

  def handle_event("toggle_all_fields", _params, socket) do
    selectable = selectable_fields(socket.assigns.rows)

    selected =
      if MapSet.subset?(selectable, socket.assigns.selected_fields),
        do: MapSet.new(),
        else: selectable

    {:noreply, assign(socket, selected_fields: selected)}
  end

  def handle_event("toggle_queue_issues", _params, socket) do
    {:noreply, update(socket, :queue_issues, &(!&1))}
  end

  def handle_event("apply", _params, %{assigns: %{selected: %Candidate{} = c, preview: preview}} = socket)
      when is_map(preview) do
    target = fresh(socket.assigns.target)
    queue_issues = socket.assigns.queue_issues
    opts = [fields: MapSet.to_list(socket.assigns.selected_fields)]
    settings = Stashix.Settings.metadata()

    socket =
      socket
      |> assign(applying: true, error: nil)
      |> start_async(:apply, fn ->
        case target do
          %Book{} ->
            Metadata.apply_issue_metadata(target, c.source_key, preview, settings, opts)

          %Series{} ->
            with {:ok, series} <- Metadata.apply_series_metadata(target, c.source_key, preview, settings, opts) do
              if queue_issues do
                Matcher.series_book_ids(series.id)
                |> Enum.each(&Metadata.enqueue_book/1)
              end

              {:ok, series}
            end
        end
      end)

    {:noreply, socket}
  end

  def handle_event("apply", _params, socket), do: {:noreply, socket}

  # ── Async results ───────────────────────────────────────────────────────────

  @impl true
  def handle_async(name, result, socket) when name in [:search, :preview] and socket.assigns.wait_until != nil,
    do: handle_async(name, result, assign(socket, wait_until: nil))

  def handle_async(:search, {:ok, {:ok, candidates}}, socket) do
    {:noreply, assign(socket, searching: false, candidates: candidates)}
  end

  def handle_async(:search, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, searching: false, candidates: [], error: Metadata.describe(reason))}
  end

  def handle_async(:preview, {:ok, {:ok, metadata}}, socket) do
    target = fresh(socket.assigns.target)

    # For books: when CV strips the issue title (format label like "TPB", "HC"),
    # surface the series/volume name as the proposed book title so the user can
    # apply it.  The Apply layer already guards against overwriting a real title.
    metadata =
      if match?(%Book{}, target) and is_nil(metadata[:title]) and is_binary(metadata[:series]) do
        Map.put(metadata, :title, metadata[:series])
      else
        metadata
      end

    rows = preview_rows(target, metadata)
    selected = socket.assigns.selected && enrich_candidate(socket.assigns.selected, metadata)

    candidates =
      Enum.map(socket.assigns.candidates, fn c ->
        if selected && c.id == selected.id && c.source_key == selected.source_key, do: selected, else: c
      end)

    {:noreply,
     assign(socket,
       selected: selected,
       candidates: candidates,
       loading_preview: false,
       preview: metadata,
       rows: rows,
       selected_fields: rows |> Enum.filter(& &1.default) |> MapSet.new(& &1.key)
     )}
  end

  def handle_async(:preview, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, loading_preview: false, error: Metadata.describe(reason))}
  end

  def handle_async(:apply, {:ok, {:ok, updated}}, socket) do
    kind = if match?(%Series{}, updated), do: :series, else: :book
    send(self(), {:identify_applied, kind, updated.id})
    # Stay in the applying state: the parent closes the dialog next.
    {:noreply, socket}
  end

  def handle_async(:apply, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, applying: false, error: Metadata.describe(reason))}
  end

  def handle_async(name, {:exit, reason}, socket) do
    {:noreply,
     assign(socket,
       searching: false,
       loading_preview: false,
       applying: false,
       error: "#{name} failed: #{inspect(reason)}"
     )}
  end

  # The parent's struct may be stale (e.g. edited since the dialog opened).
  defp fresh(%mod{id: id}), do: Repo.get!(mod, id)

  defp blank_to_nil(v) when v in [nil, ""], do: nil
  defp blank_to_nil(v), do: String.trim(v)

  defp int(v) when v in [nil, ""], do: nil

  defp int(v) do
    case Integer.parse(to_string(v)) do
      {i, _} -> i
      :error -> nil
    end
  end

  # ── Preview rows ────────────────────────────────────────────────────────────
  #
  # Each row: %{key, label, current, new, selectable, default}. `key` is the
  # Apply field key (string) or nil for info-only rows. Selectable rows are
  # pre-checked when the current value is empty ("fill empty"); overwriting a
  # populated field is opt-in.

  @book_rows [
    {"title", "Title"},
    {nil, "Series"},
    {"issue_number", "Number"},
    {"volume", "Volume"},
    {"cover_date", "Cover date"},
    {"store_date", "Store date"},
    {"year", "Year"},
    {"publisher", "Publisher"},
    {"imprint", "Imprint"},
    {"collection_title", "Collection title"},
    {"alternative_number", "Alt. number"},
    {"age_rating", "Age rating"},
    {"language", "Language"},
    {"page_count", "Pages"},
    {"isbn", "ISBN"},
    {"upc", "UPC"},
    {"community_rating", "Rating"},
    {"summary", "Summary"},
    {"notes", "Notes"},
    {"stories", "Stories"},
    {"credits", "Credits"},
    {"characters", "Characters"},
    {"teams", "Teams"},
    {"locations", "Locations"},
    {"universes", "Universes"},
    {"arcs", "Story arcs"},
    {"genres", "Genres"},
    {"tags", "Tags"},
    {"reprints", "Reprints"},
    {"prices", "Prices"},
    {"urls", "Links"}
  ]

  @series_rows [
    {nil, "Name"},
    {"sort_name", "Sort name"},
    {"volume", "Volume"},
    {"format", "Format"},
    {"start_year", "Start year"},
    {"end_year", "End year"},
    {"ongoing", "Ongoing"},
    {"issue_count", "Issues"},
    {"publisher", "Publisher"},
    {"language", "Language"},
    {"summary", "Summary"}
  ]

  @child_assocs %{
    "stories" => :stories,
    "credits" => :credits,
    "characters" => :characters,
    "teams" => :teams,
    "locations" => :locations,
    "universes" => :universes,
    "arcs" => :story_arcs,
    "genres" => :genres,
    "tags" => :tags,
    "reprints" => :reprints,
    "prices" => :prices,
    "urls" => :urls
  }

  defp preview_rows(%Book{} = book, m) do
    book =
      Repo.preload(book, [
        :series,
        :publishers,
        :imprint,
        :files,
        :stories,
        :characters,
        :teams,
        :locations,
        :universes,
        :story_arcs,
        :genres,
        :tags,
        :reprints,
        :prices,
        :urls,
        credits: :creator
      ])

    # Standalone when the series already has issue_count 1, OR when the CV volume
    # name matches the current book title (series IS the title — typical TPB pattern).
    standalone =
      match?(%{series: %{issue_count: 1}}, book) or
        (is_binary(m[:series]) and is_binary(book.title) and
           normalize_title(m[:series]) == normalize_title(book.title))

    @book_rows
    |> Enum.map(fn
      {nil, label} ->
        info_row(label, book.series && book.series.name, m[:series])

      {"issue_number", label} ->
        {current_raw, current} = book_current(book, "issue_number")
        new_raw = m[:issue_number]
        r = row("issue_number", label, current_raw, current, new_raw, display_new("issue_number", new_raw))
        # Standalone CV volumes always have issue_number 1 — don't auto-select it
        if standalone, do: %{r | default: false}, else: r

      {"urls", label} ->
        # Links are merged one per source (see Importer.merge_urls/2): show the resulting
        # list and pre-check it when it changes anything.
        # First link per source wins, as in merge_urls.
        incoming =
          (m[:urls] || [])
          |> Enum.reverse()
          |> Map.new(&{Importer.link_source(&1.url), String.trim(&1.url)})

        known = MapSet.new(book.urls, &String.trim(&1.url))
        added = incoming |> Map.values() |> Enum.reject(&MapSet.member?(known, &1))

        # Replaced links stay in place; links from new sources are appended.
        merged =
          Enum.map(book.urls, &Map.get(incoming, Importer.link_source(&1.url), &1.url))
          |> Enum.concat(Map.values(incoming))
          |> Enum.uniq_by(&Importer.link_source/1)

        current = summarize("urls", book.urls)
        added = Enum.map(added, &%{url: &1})
        r = row("urls", label, book.urls, current, added, preview_join(merged))
        %{r | default: r.selectable}

      {key, label} ->
        {current_raw, current} = book_current(book, key)
        new_raw = m[String.to_existing_atom(key)]
        row(key, label, current_raw, current, new_raw, display_new(key, new_raw))
    end)
    |> Enum.reject(&(&1.current == nil and &1.new == nil))
  end

  defp preview_rows(%Series{} = series, m) do
    series = Repo.preload(series, :publishers)

    @series_rows
    |> Enum.map(fn
      {nil, label} ->
        info_row(label, series.name, m[:name])

      {"publisher", label} ->
        current = series.publishers |> Enum.map(& &1.name) |> join_or_nil()
        row("publisher", label, current, current, m[:publisher], m[:publisher])

      {key, label} ->
        current = Map.get(series, String.to_existing_atom(key))
        new = m[String.to_existing_atom(key)]
        row(key, label, current, fmt(current), new, fmt(new))
    end)
    |> Enum.reject(&(&1.current == nil and &1.new == nil))
  end

  defp book_current(book, "title"), do: {Apply.current_value(book, :title), book.title}
  defp book_current(book, "publisher"), do: book.publishers |> Enum.map(& &1.name) |> join_or_nil() |> dup()
  defp book_current(book, "imprint"), do: dup(book.imprint && book.imprint.name)
  defp book_current(book, "issue_number"), do: dup(Matcher.format_number(book.issue_number))
  defp book_current(book, "page_count"), do: dup(if(book.page_count in [nil, 0], do: nil, else: book.page_count))

  defp book_current(book, key) when is_map_key(@child_assocs, key) do
    items = Map.get(book, @child_assocs[key])
    {items, summarize(key, items)}
  end

  defp book_current(book, key) do
    v = Map.get(book, String.to_existing_atom(key))
    {v, fmt(v)}
  end

  defp dup(v), do: {v, fmt(v)}

  defp display_new("issue_number", v), do: Matcher.format_number(v)
  defp display_new(key, items) when is_map_key(@child_assocs, key), do: summarize(key, items)
  defp display_new(_key, v), do: fmt(v)

  defp row(key, label, current_raw, current, new_raw, new) do
    selectable = Apply.present?(new_raw) and new != current

    %{
      key: key,
      label: label,
      current: current,
      new: new,
      selectable: selectable,
      default: selectable and not Apply.present?(current_raw)
    }
  end

  defp info_row(label, current, new),
    do: %{key: nil, label: label, current: fmt(current), new: fmt(new), selectable: false, default: false}

  defp selectable_fields(rows), do: rows |> Enum.filter(& &1.selectable) |> MapSet.new(& &1.key)

  defp normalize_title(s), do: s |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")

  # Child lists from the DB (structs) or from a source (maps) → short text.
  defp summarize(_key, items) when items in [nil, []], do: nil

  defp summarize("credits", items) do
    items
    |> Enum.map(fn
      %{creator: %{name: name}, role: role} -> {name, to_string(role)}
      %{creator: name, roles: roles} -> {name, Enum.join(roles, "/")}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {name, roles} -> "#{name} (#{Enum.join(Enum.uniq(roles), ", ")})" end)
    |> preview_join()
  end

  defp summarize("prices", items), do: items |> Enum.map(&"#{&1.amount} #{&1.country}") |> preview_join()
  defp summarize("urls", items), do: items |> Enum.map(& &1.url) |> preview_join()
  defp summarize(_key, items), do: items |> Enum.map(&item_name/1) |> preview_join()

  defp item_name(s) when is_binary(s), do: s
  defp item_name(%{name: n}), do: n

  defp preview_join(list) do
    list = Enum.uniq(list)
    {shown, rest} = Enum.split(list, 6)
    text = Enum.join(shown, ", ")
    if rest == [], do: text, else: "#{text} +#{length(rest)} more"
  end

  defp join_or_nil([]), do: nil
  defp join_or_nil(list), do: Enum.join(list, ", ")

  defp fmt(nil), do: nil
  defp fmt(""), do: nil
  defp fmt(:unknown), do: nil
  defp fmt(%Decimal{} = d), do: Decimal.to_string(d, :normal)
  defp fmt(true), do: "Yes"
  defp fmt(false), do: "No"
  defp fmt(v) when is_binary(v) and byte_size(v) > 160, do: String.slice(v, 0, 160) <> "…"
  defp fmt(v), do: to_string(v)

  defp source_name(sources, key), do: Enum.find_value(sources, key, fn {k, n} -> if k == key, do: n end)

  # ── Render ──────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="fixed inset-0 z-50 overflow-y-auto"
      phx-window-keydown="close_identify_dialog"
      phx-key="Escape"
    >
      <div class="fixed inset-0 bg-black/80" phx-click="close_identify_dialog" aria-hidden="true"></div>
      <div class="relative min-h-full flex items-start sm:items-center justify-center p-4 pointer-events-none">
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby={"#{@id}-title"}
          phx-mounted={JS.transition({"ease-out duration-150", "opacity-0 scale-95", "opacity-100 scale-100"}, time: 150)}
          class="pointer-events-auto relative w-full max-w-3xl rounded-lg border border-gray-700 bg-gray-900 p-6 text-white shadow-xl"
        >
          <button
            type="button"
            phx-click="close_identify_dialog"
            class="absolute right-4 top-4 text-gray-500 hover:text-white"
            aria-label="Close"
          >
            <.icon name="lucide-x" class="w-4 h-4" />
          </button>

          <h2 id={"#{@id}-title"} class="text-lg font-semibold">
            {if @kind == :series, do: "Identify Series", else: "Identify Issue"}
          </h2>
          <p class="text-sm text-gray-400">Search a metadata source and pick the matching entry.</p>
          <%= if @kind == :issue && @target.files != [] do %>
            <p class="text-[11px] text-gray-600 font-mono truncate mb-4 mt-0.5">
              {@target.library.name <> "/" <> Path.relative_to(List.first(@target.files).path, @target.library.root_path)}
            </p>
          <% else %>
            <div class="mb-4" />
          <% end %>

          <div :if={@known_ids != %{}} class="flex flex-wrap items-center gap-2 mb-4 text-xs">
            <span class="text-gray-500">Linked IDs:</span>
            <button
              :for={{key, id} <- @known_ids}
              type="button"
              phx-click="lookup_known"
              phx-value-source={key}
              phx-target={@myself}
              title="Look up this entry directly"
              class="inline-flex items-center gap-1.5 rounded-md border border-gray-700 bg-gray-800/60 px-2 py-1 text-gray-300 hover:border-violet-500 hover:text-white transition-colors"
            >
              <.icon name="lucide-link" class="w-3 h-3" />
              {source_name(@sources, key)} <span class="font-mono text-gray-500">{"##{id}"}</span>
            </button>
          </div>

          <%= if @sources == [] do %>
            <div class="rounded-lg border border-amber-700/50 bg-amber-900/20 p-4 text-sm text-amber-200">
              No metadata source is enabled and configured. <.link
                navigate={~p"/admin/metadata"}
                class="underline hover:text-white"
              >
                Set one up in Admin · Metadata
              </.link>.
            </div>
          <% else %>
            <.form
              for={@form}
              id={"#{@id}-search"}
              phx-submit="search"
              phx-target={@myself}
              class="grid grid-cols-2 sm:grid-cols-6 gap-3 items-end"
            >
              <div class="col-span-2 sm:col-span-2">
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Source</label>
                <.ink_select
                  id={"#{@id}-source"}
                  name="source"
                  label="Source"
                  variant="field"
                  value={@source_key}
                  options={Enum.map(@sources, fn {key, name} -> {name, key} end)}
                />
              </div>
              <div class={if @kind == :series, do: "col-span-2 sm:col-span-3", else: "col-span-2 sm:col-span-2"}>
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Series</label>
                <input type="text" name="q[series_name]" value={@form[:series_name].value} class={input_class()} />
              </div>
              <%= if @kind == :issue do %>
                <div>
                  <label class="block text-xs font-medium text-gray-400 mb-1.5">Number</label>
                  <input type="text" name="q[number]" value={@form[:number].value} class={input_class()} />
                </div>
              <% end %>
              <div>
                <label class="block text-xs font-medium text-gray-400 mb-1.5">Year</label>
                <input type="text" name="q[year]" value={@form[:year].value} class={input_class()} />
              </div>
              <div class="col-span-2 sm:col-span-6 flex items-center justify-end gap-4">
                <label class="flex items-center gap-2 text-xs text-gray-500" title="Ignore cached responses">
                  <input type="hidden" name="refresh" value="false" />
                  <input
                    type="checkbox"
                    name="refresh"
                    value="true"
                    checked={@refresh}
                    class="rounded border-gray-600 bg-gray-800 text-violet-600"
                  /> Skip cache
                </label>
                <button
                  type="submit"
                  disabled={@searching}
                  class="inline-flex items-center gap-1.5 rounded-md px-4 py-2 text-sm font-medium bg-violet-600 hover:bg-violet-500 disabled:opacity-60 text-white"
                >
                  <.icon
                    name={if @searching, do: "lucide-loader-circle", else: "lucide-search"}
                    class={if @searching, do: "w-4 h-4 animate-spin", else: "w-4 h-4"}
                  /> {if @searching, do: "Searching…", else: "Search"}
                </button>
              </div>
            </.form>

            <div
              :if={@linked_lookup}
              class="mt-3 flex items-start gap-2 rounded-lg border border-violet-800/50 bg-violet-900/20 px-3 py-2 text-sm text-violet-200"
            >
              <.icon name="lucide-link" class="w-4 h-4 mt-0.5 flex-shrink-0" />
              <p>
                <% {key, id} = @linked_lookup %> This {if @kind == :series, do: "series", else: "issue"} is already linked to
                <span class="font-medium text-white">{source_name(@sources, key)}</span>
                <span class="font-mono">{"##{id}"}</span>
                (from its file tags or an earlier match), so that entry was loaded directly — no search needed.
                <span class="text-violet-300/70">Not the right match? Search above to pick a different one.</span>
              </p>
            </div>

            <.rate_wait_note
              :if={@searching}
              wait_until={@wait_until}
              source={source_name(@sources, @source_key)}
              limit={@wait_limit}
            />

            <div
              :if={@error}
              class="mt-3 rounded-lg border border-red-800/60 bg-red-900/20 px-3 py-2 text-sm text-red-300"
            >
              {@error}
            </div>

            <div
              id={"#{@id}-candidates"}
              class={[
                "mt-4 space-y-1.5 max-h-72 min-h-24 overflow-y-auto pr-1 transition-opacity",
                @searching && "opacity-50"
              ]}
            >
              <p :if={@candidates == [] and not @searching} class="text-sm text-gray-500 py-6 text-center">
                No results yet.
              </p>
              <p
                :if={@candidates == [] and @searching}
                role="status"
                class="flex items-center justify-center gap-2 text-sm text-gray-400 py-6"
              >
                <.icon name="lucide-loader-circle" class="w-4 h-4 animate-spin" />
                Searching {source_name(@sources, @source_key)}…
              </p>
              <%= for {c, idx} <- Enum.with_index(@candidates) do %>
                <button
                  type="button"
                  id={"#{@id}-cand-#{c.source_key}-#{c.id}"}
                  phx-click="select"
                  phx-value-idx={idx}
                  phx-target={@myself}
                  class={[
                    "w-full flex items-center gap-3 rounded-lg border px-3 py-2 text-left transition-colors",
                    if(@selected && @selected.id == c.id && @selected.source_key == c.source_key,
                      do: "border-violet-500 bg-violet-900/20",
                      else: "border-gray-800 bg-gray-800/40 hover:border-gray-600"
                    )
                  ]}
                >
                  <div class="w-10 aspect-[2/3] flex-shrink-0 rounded bg-gray-800 overflow-hidden">
                    <img
                      :if={c.cover_url}
                      id={"#{@id}-cover-#{c.source_key}-#{c.id}"}
                      src={~p"/api/metadata/image?#{[url: c.cover_url]}"}
                      alt=""
                      loading="lazy"
                      class="w-full h-full object-cover"
                    />
                  </div>
                  <div class="min-w-0 flex-1">
                    <p class="text-sm text-white truncate">{c.title || c.series_name}</p>
                    <p class="text-xs text-gray-500 truncate">
                      {[
                        c.series_name,
                        c.number && "##{c.number}",
                        c.year,
                        c.publisher,
                        c.issue_count && "#{c.issue_count} issues"
                      ]
                      |> Enum.reject(&is_nil/1)
                      |> Enum.join(" · ")}
                    </p>
                  </div>
                  <span
                    :if={linked?(@known_ids, c)}
                    class="inline-flex items-center gap-1 text-[10px] uppercase tracking-wide text-violet-300 flex-shrink-0"
                  >
                    <.icon name="lucide-link" class="w-3 h-3" /> Linked
                  </span>
                  <span class="text-[10px] uppercase tracking-wide text-gray-500 flex-shrink-0">
                    {source_name(@sources, c.source_key)}
                  </span>
                  <span class={[
                    "text-xs font-mono px-1.5 py-0.5 rounded flex-shrink-0",
                    cond do
                      c.score >= 0.9 -> "bg-emerald-900/40 text-emerald-300"
                      c.score >= 0.7 -> "bg-amber-900/40 text-amber-300"
                      true -> "bg-gray-800 text-gray-400"
                    end
                  ]}>
                    {round(c.score * 100)}%
                  </span>
                  <a
                    :if={c.url}
                    href={c.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="text-gray-500 hover:text-white flex-shrink-0"
                    title="Open on source site"
                  >
                    <.icon name="lucide-external-link" class="w-4 h-4" />
                  </a>
                </button>
              <% end %>
            </div>

            <div id={"#{@id}-preview"} class="mt-4">
              <p
                :if={@loading_preview and wait_remaining(@wait_until) == 0}
                class="flex items-center gap-2 text-sm text-gray-400 py-4"
              >
                <.icon name="lucide-loader-circle" class="w-4 h-4 animate-spin" /> Loading details…
              </p>
              <.rate_wait_note
                :if={@loading_preview}
                wait_until={@wait_until}
                source={source_name(@sources, @selected.source_key)}
                limit={@wait_limit}
              />

              <div :if={@preview} class="rounded-lg border border-gray-800 overflow-x-auto">
                <table class="w-full text-sm">
                  <thead class="bg-gray-800/60 text-xs text-gray-400">
                    <tr>
                      <th class="w-8 px-3 py-2">
                        <input
                          type="checkbox"
                          phx-click="toggle_all_fields"
                          phx-target={@myself}
                          checked={
                            MapSet.size(@selected_fields) > 0 and
                              MapSet.subset?(selectable_fields(@rows), @selected_fields)
                          }
                          title="Select all"
                          class="rounded border-gray-600 bg-gray-800 text-violet-600"
                        />
                      </th>
                      <th class="text-left font-medium px-3 py-2 w-32">Field</th>
                      <th class="text-left font-medium px-3 py-2">Current</th>
                      <th class="text-left font-medium px-3 py-2">New</th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-gray-800">
                    <%= for row <- @rows do %>
                      <% checked = row.key != nil and MapSet.member?(@selected_fields, row.key) %>
                      <tr id={"#{@id}-row-#{row.key || row.label}"}>
                        <td class="px-3 py-1.5 align-top">
                          <input
                            :if={row.selectable}
                            type="checkbox"
                            phx-click="toggle_field"
                            phx-value-field={row.key}
                            phx-target={@myself}
                            checked={checked}
                            class="rounded border-gray-600 bg-gray-800 text-violet-600"
                          />
                        </td>
                        <td class="px-3 py-1.5 text-gray-500 align-top">{row.label}</td>
                        <td class={[
                          "px-3 py-1.5 align-top",
                          if(checked && row.current, do: "text-gray-600 line-through", else: "text-gray-400")
                        ]}>
                          {row.current || "—"}
                        </td>
                        <td class={[
                          "px-3 py-1.5 align-top",
                          cond do
                            checked -> "text-emerald-300"
                            row.selectable -> "text-gray-500"
                            true -> "text-gray-600"
                          end
                        ]}>
                          {row.new || "—"}
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
              <p :if={@preview} class="mt-2 text-xs text-gray-500">
                Checked fields are written. Empty fields are selected by default; tick a filled field to overwrite it.
              </p>
            </div>
          <% end %>

          <div class="pt-5 flex flex-wrap items-center justify-end gap-3">
            <label :if={@kind == :series} class="mr-auto flex items-center gap-2 text-sm text-gray-400">
              <input
                type="checkbox"
                checked={@queue_issues}
                phx-click="toggle_queue_issues"
                phx-target={@myself}
                class="rounded border-gray-600 bg-gray-800 text-violet-600"
              /> Then match all issues
            </label>
            <button
              type="button"
              phx-click="close_identify_dialog"
              class="inline-flex items-center justify-center rounded-md px-4 py-2 text-sm font-medium border border-gray-700 text-gray-300 hover:bg-gray-800"
            >
              Cancel
            </button>
            <button
              type="button"
              phx-click="apply"
              phx-target={@myself}
              disabled={is_nil(@preview) or @applying}
              class="inline-flex items-center justify-center gap-1.5 rounded-md px-4 py-2 text-sm font-medium bg-emerald-600 hover:bg-emerald-500 disabled:opacity-50 disabled:cursor-not-allowed text-white"
            >
              <.icon :if={@applying} name="lucide-loader-circle" class="w-4 h-4 animate-spin" />
              <%= if @applying do %>
                Applying…
              <% else %>
                Apply {if @preview, do: "(#{MapSet.size(@selected_fields)})"}
              <% end %>
            </button>
          </div>

          <div
            :if={@applying}
            id={"#{@id}-applying"}
            role="status"
            class="absolute inset-0 z-10 flex flex-col items-center justify-center gap-3 rounded-lg bg-gray-900/80 text-sm text-gray-200"
          >
            <.icon name="lucide-loader-circle" class="w-8 h-8 animate-spin text-emerald-400" />
            <p>Applying metadata…</p>
            <p :if={@kind == :series and @queue_issues} class="text-xs text-gray-500">
              Issues are queued for matching afterwards.
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :wait_until, :integer, default: nil
  attr :source, :string, required: true
  attr :limit, :any, default: nil

  defp rate_wait_note(assigns) do
    assigns = assign(assigns, secs: ceil(wait_remaining(assigns.wait_until) / 1000))

    ~H"""
    <div
      :if={@secs > 0}
      class="mt-3 flex items-start gap-2 rounded-lg border border-amber-700/50 bg-amber-900/20 px-3 py-2 text-sm text-amber-200"
    >
      <.icon name="lucide-hourglass" class="w-4 h-4 mt-0.5 flex-shrink-0 animate-pulse" />
      <div>
        <p>Waiting for {@source}'s rate limit, next request in {@secs}s…</p>
        <p :if={@limit} class="text-xs text-amber-300/70">
          {@source} allows {rate_text(@limit)}. Searches can take several requests; cached results skip the wait.
        </p>
      </div>
    </div>
    """
  end

  defp rate_text({1, ms}), do: "one request every #{Float.round(ms / 1000, 1)}s"
  defp rate_text({n, 3_600_000}), do: "#{n} requests per hour for this endpoint"
  defp rate_text({n, 60_000}), do: "#{n} requests per minute"
  defp rate_text({n, ms}), do: "#{n} requests per #{div(ms, 1000)}s"
end
