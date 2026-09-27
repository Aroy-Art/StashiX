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
  alias Stashix.Metadata.{Apply, Candidate, Matcher, Sources}
  alias Stashix.Library.{Book, Series}

  @impl true
  def update(assigns, socket) do
    first_mount? = not Map.has_key?(socket.assigns, :kind)
    socket = assign(socket, assigns)

    if first_mount? do
      {:ok, init(socket)}
    else
      {:ok, socket}
    end
  end

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

    socket
    |> assign(
      kind: kind,
      sources: sources,
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
      |> assign(selected: nil, preview: nil, rows: [])
      |> start_async(:search, fn ->
        Metadata.search(source_key, if(kind == :series, do: :series, else: :issue), query, refresh: refresh)
      end)

    {:noreply, socket}
  end

  def handle_event("select", %{"idx" => idx}, socket) do
    candidate = Enum.at(socket.assigns.candidates, String.to_integer(idx))
    kind = socket.assigns.kind
    opts = [refresh: socket.assigns.refresh]

    socket =
      socket
      |> assign(selected: candidate, preview: nil, rows: [], loading_preview: true, error: nil)
      |> start_async(:preview, fn ->
        if kind == :series,
          do: Metadata.fetch_series(candidate.source_key, candidate.id, opts),
          else: Metadata.fetch_issue(candidate.source_key, candidate.id, opts)
      end)

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
  def handle_async(:search, {:ok, {:ok, candidates}}, socket) do
    {:noreply, assign(socket, searching: false, candidates: candidates)}
  end

  def handle_async(:search, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, searching: false, candidates: [], error: Metadata.describe(reason))}
  end

  def handle_async(:preview, {:ok, {:ok, metadata}}, socket) do
    rows = preview_rows(fresh(socket.assigns.target), metadata)

    {:noreply,
     assign(socket,
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
    {:noreply, assign(socket, applying: false)}
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

    @book_rows
    |> Enum.map(fn
      {nil, label} ->
        info_row(label, book.series && book.series.name, m[:series])

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
          <p class="text-sm text-gray-400 mb-4">Search a metadata source and pick the matching entry.</p>

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
                <select name="source" class={input_class()}>
                  <%= for {key, name} <- @sources do %>
                    <option value={key} selected={key == @source_key}>{name}</option>
                  <% end %>
                </select>
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
                  /> Search
                </button>
              </div>
            </.form>

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
                      src={c.cover_url}
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
              <p :if={@loading_preview} class="flex items-center gap-2 text-sm text-gray-400 py-4">
                <.icon name="lucide-loader-circle" class="w-4 h-4 animate-spin" /> Loading details…
              </p>

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
              Apply {if @preview, do: "(#{MapSet.size(@selected_fields)})"}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp input_class,
    do:
      "w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
end
