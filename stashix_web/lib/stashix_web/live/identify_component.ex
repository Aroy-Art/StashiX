defmodule StashixWeb.IdentifyComponent do
  @moduledoc """
  "Identify" dialog: search a metadata source for a book (issue) or series,
  preview a result against the current data and apply it.

  The parent LiveView renders it while its identify dialog is open and handles
  `"close_identify_dialog"` plus `{:identify_applied, kind, id}` messages.
  Pass `review` to start from a stored review's query and candidates.
  """
  use StashixWeb, :live_component

  alias Stashix.Metadata
  alias Stashix.Metadata.{Candidate, Matcher, Sources}
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
      candidates: candidates,
      selected: nil,
      preview: nil,
      error: review && review.error,
      searching: false,
      loading_preview: false,
      applying: false,
      queue_issues: true
    )
  end

  defp first_key([{k, _} | _]), do: k
  defp first_key(_), do: nil

  defp stringify(query), do: Map.new(query, fn {k, v} -> {to_string(k), if(is_nil(v), do: "", else: to_string(v))} end)

  @impl true
  def handle_event("search", %{"q" => q} = params, socket) do
    source_key = params["source"] || socket.assigns.source_key
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
      |> assign(source_key: source_key, form: to_form(q, as: :q), searching: true, error: nil)
      |> assign(selected: nil, preview: nil)
      |> start_async(:search, fn ->
        Metadata.search(source_key, if(kind == :series, do: :series, else: :issue), query)
      end)

    {:noreply, socket}
  end

  def handle_event("select", %{"idx" => idx}, socket) do
    candidate = Enum.at(socket.assigns.candidates, String.to_integer(idx))
    kind = socket.assigns.kind

    socket =
      socket
      |> assign(selected: candidate, preview: nil, loading_preview: true, error: nil)
      |> start_async(:preview, fn ->
        if kind == :series,
          do: Metadata.fetch_series(candidate.source_key, candidate.id),
          else: Metadata.fetch_issue(candidate.source_key, candidate.id)
      end)

    {:noreply, socket}
  end

  def handle_event("toggle_queue_issues", _params, socket) do
    {:noreply, update(socket, :queue_issues, &(!&1))}
  end

  def handle_event("apply", _params, %{assigns: %{selected: %Candidate{} = c, preview: preview}} = socket)
      when is_map(preview) do
    target = socket.assigns.target
    queue_issues = socket.assigns.queue_issues

    socket =
      socket
      |> assign(applying: true, error: nil)
      |> start_async(:apply, fn ->
        case target do
          %Book{} ->
            Metadata.apply_issue_metadata(target, c.source_key, preview)

          %Series{} ->
            with {:ok, series} <- Metadata.apply_series_metadata(target, c.source_key, preview) do
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

  @impl true
  def handle_async(:search, {:ok, {:ok, candidates}}, socket) do
    {:noreply, assign(socket, searching: false, candidates: candidates)}
  end

  def handle_async(:search, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, searching: false, candidates: [], error: Metadata.describe(reason))}
  end

  def handle_async(:preview, {:ok, {:ok, metadata}}, socket) do
    {:noreply, assign(socket, loading_preview: false, preview: metadata)}
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

  defp preview_rows(%Book{} = book, m) do
    book = Stashix.Repo.preload(book, [:series, :publishers, :credits, :characters])

    [
      {"Title", book.title, m[:title]},
      {"Series", book.series && book.series.name, m[:series]},
      {"Number", Matcher.format_number(book.issue_number), Matcher.format_number(m[:issue_number])},
      {"Cover date", book.cover_date, m[:cover_date]},
      {"Publisher", Enum.map_join(book.publishers, ", ", & &1.name), m[:publisher]},
      {"Age rating", book.age_rating, m[:age_rating]},
      {"Summary", truncate(book.summary), truncate(m[:summary])},
      {"Credits", count(book.credits), count(m[:credits])},
      {"Characters", count(book.characters), count(m[:characters])}
    ]
  end

  defp preview_rows(%Series{} = series, m) do
    series = Stashix.Repo.preload(series, :publishers)

    [
      {"Name", series.name, m[:name]},
      {"Start year", series.start_year, m[:start_year]},
      {"End year", series.end_year, m[:end_year]},
      {"Publisher", Enum.map_join(series.publishers, ", ", & &1.name), m[:publisher]},
      {"Format", series.format, m[:format]},
      {"Issues", series.issue_count, m[:issue_count]},
      {"Summary", truncate(series.summary), truncate(m[:summary])}
    ]
  end

  defp count(list) when is_list(list), do: length(list)
  defp count(_), do: nil

  defp truncate(nil), do: nil
  defp truncate(s) when byte_size(s) > 140, do: String.slice(s, 0, 140) <> "…"
  defp truncate(s), do: s

  defp display(nil), do: "—"
  defp display(""), do: "—"
  defp display(v), do: to_string(v)

  defp source_name(sources, key), do: Enum.find_value(sources, key, fn {k, n} -> if k == key, do: n end)

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.dialog id={"#{@id}-dialog"} open={true} on-close={JS.push("close_identify_dialog")}>
        <.dialog_content class="sm:max-w-3xl !bg-gray-900 !border-gray-700 text-white max-h-[90vh] overflow-y-auto">
          <.dialog_header>
            <.dialog_title class="text-white">
              {if @kind == :series, do: "Identify Series", else: "Identify Issue"}
            </.dialog_title>
            <.dialog_description class="text-gray-400">
              Search a metadata source and pick the matching entry.
            </.dialog_description>
          </.dialog_header>

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
              <div class="col-span-2 sm:col-span-6 flex justify-end">
                <button
                  type="submit"
                  disabled={@searching}
                  class="inline-flex items-center gap-1.5 rounded-md px-4 py-2 text-sm font-medium bg-violet-600 hover:bg-violet-500 disabled:opacity-60 text-white"
                >
                  <%= if @searching do %>
                    <.icon name="lucide-loader-circle" class="w-4 h-4 animate-spin" /> Searching…
                  <% else %>
                    <.icon name="lucide-search" class="w-4 h-4" /> Search
                  <% end %>
                </button>
              </div>
            </.form>

            <%= if @error do %>
              <div class="mt-3 rounded-lg border border-red-800/60 bg-red-900/20 px-3 py-2 text-sm text-red-300">
                {@error}
              </div>
            <% end %>

            <div class="mt-4 space-y-1.5 max-h-80 overflow-y-auto pr-1">
              <%= if @candidates == [] and not @searching do %>
                <p class="text-sm text-gray-500 py-6 text-center">No results yet.</p>
              <% end %>
              <%= for {c, idx} <- Enum.with_index(@candidates) do %>
                <button
                  type="button"
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
                    <%= if c.cover_url do %>
                      <img src={c.cover_url} alt="" loading="lazy" class="w-full h-full object-cover" />
                    <% end %>
                  </div>
                  <div class="min-w-0 flex-1">
                    <p class="text-sm text-white truncate">
                      {c.title || c.series_name}
                    </p>
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
                  <%= if c.url do %>
                    <a
                      href={c.url}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="text-gray-500 hover:text-white flex-shrink-0"
                      title="Open on source site"
                    >
                      <.icon name="lucide-external-link" class="w-4 h-4" />
                    </a>
                  <% end %>
                </button>
              <% end %>
            </div>

            <%= if @loading_preview do %>
              <div class="mt-4 flex items-center gap-2 text-sm text-gray-400">
                <.icon name="lucide-loader-circle" class="w-4 h-4 animate-spin" /> Loading details…
              </div>
            <% end %>

            <%= if @preview do %>
              <div class="mt-4 rounded-lg border border-gray-800 overflow-hidden">
                <table class="w-full text-sm">
                  <thead class="bg-gray-800/60 text-xs text-gray-400">
                    <tr>
                      <th class="text-left font-medium px-3 py-2 w-28">Field</th>
                      <th class="text-left font-medium px-3 py-2">Current</th>
                      <th class="text-left font-medium px-3 py-2">New</th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-gray-800">
                    <%= for {label, current, new} <- preview_rows(@target, @preview) do %>
                      <tr>
                        <td class="px-3 py-1.5 text-gray-500 align-top">{label}</td>
                        <td class="px-3 py-1.5 text-gray-400 align-top">{display(current)}</td>
                        <td class={[
                          "px-3 py-1.5 align-top",
                          if(display(new) != display(current) and new not in [nil, ""],
                            do: "text-emerald-300",
                            else: "text-gray-400"
                          )
                        ]}>
                          {display(new)}
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          <% end %>

          <.dialog_footer class="pt-4 flex items-center gap-3">
            <%= if @kind == :series do %>
              <label class="mr-auto flex items-center gap-2 text-sm text-gray-400">
                <input
                  type="checkbox"
                  checked={@queue_issues}
                  phx-click="toggle_queue_issues"
                  phx-target={@myself}
                  class="rounded border-gray-600 bg-gray-800 text-violet-600"
                /> Then match all issues
              </label>
            <% end %>
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
              <%= if @applying do %>
                <.icon name="lucide-loader-circle" class="w-4 h-4 animate-spin" /> Applying…
              <% else %>
                Apply
              <% end %>
            </button>
          </.dialog_footer>
        </.dialog_content>
      </.dialog>
    </div>
    """
  end

  defp input_class,
    do:
      "w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
end
