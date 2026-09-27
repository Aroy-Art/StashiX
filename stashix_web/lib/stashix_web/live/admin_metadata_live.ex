defmodule StashixWeb.AdminMetadataLive do
  @moduledoc "Admin · Metadata: source plugins, match settings, review queue and jobs."
  use StashixWeb, :live_view

  alias Stashix.{Library, Metadata, Settings}
  alias Stashix.Metadata.Sources

  on_mount {StashixWeb.Live.Hooks, :require_admin}

  @job_refresh_ms 3_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Metadata.subscribe_admin()

    {:ok,
     assign(socket,
       admin_sidebar: true,
       sources: [],
       testing: MapSet.new(),
       saved: nil,
       settings: Settings.metadata(),
       reviews: [],
       review_count: Metadata.count_reviews(),
       identify_review: nil,
       job_counts: %{},
       libraries: [],
       refresh_timer: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :metadata_sources, _params) do
    socket
    |> assign(page_title: "Admin · Metadata")
    |> load_sources()
  end

  defp apply_action(socket, :metadata_settings, _params) do
    assign(socket, page_title: "Admin · Metadata Settings", settings: Settings.metadata())
  end

  defp apply_action(socket, :metadata_review, params) do
    socket = assign(socket, page_title: "Admin · Metadata Review") |> load_reviews()

    case params["identify"] do
      nil ->
        assign(socket, identify_review: nil)

      id ->
        review = Metadata.get_review!(id)
        if review.status == "pending", do: assign(socket, identify_review: review), else: socket
    end
  end

  defp apply_action(socket, :metadata_jobs, _params) do
    socket
    |> assign(page_title: "Admin · Metadata Jobs", libraries: Library.list_libraries(%{role: :admin}))
    |> load_jobs()
  end

  defp load_sources(socket), do: assign(socket, sources: Sources.list())

  defp load_reviews(socket),
    do: assign(socket, reviews: Metadata.list_reviews(), review_count: Metadata.count_reviews())

  defp load_jobs(socket) do
    if socket.assigns.refresh_timer, do: Process.cancel_timer(socket.assigns.refresh_timer)

    timer =
      if connected?(socket) and socket.assigns.live_action == :metadata_jobs,
        do: Process.send_after(self(), :refresh_jobs, @job_refresh_ms)

    assign(socket, job_counts: Metadata.job_counts(), refresh_timer: timer)
  end

  defp source_row(socket, key), do: Enum.find(socket.assigns.sources, &(&1.config.source_key == key))

  # ── Sources ─────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("toggle_source", %{"key" => key, "field" => field}, socket)
      when field in ["enabled", "auto_apply"] do
    %{config: row} = source_row(socket, key)
    {:ok, _} = Sources.update(row, %{field => not Map.fetch!(row, String.to_existing_atom(field))})
    {:noreply, load_sources(socket)}
  end

  def handle_event("move_source", %{"key" => key, "dir" => dir}, socket) do
    Sources.move(key, if(dir == "up", do: :up, else: :down))
    {:noreply, load_sources(socket)}
  end

  def handle_event("save_source", %{"key" => key} = params, socket) do
    %{config: row} = source_row(socket, key)

    attrs = %{
      "config" => Map.get(params, "config", %{}),
      "rate_limit_per_minute" =>
        case Integer.parse(params["rate_limit_per_minute"] || "") do
          {n, _} when n > 0 -> n
          _ -> nil
        end
    }

    case Sources.update(row, attrs) do
      {:ok, _} ->
        Stashix.Metadata.RateLimiter.reset(key)
        {:noreply, socket |> load_sources() |> assign(saved: key) |> put_flash(:info, "Saved")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Could not save: #{inspect(changeset.errors)}")}
    end
  end

  def handle_event("test_source", %{"key" => key}, socket) do
    pid = self()

    Task.start(fn ->
      Metadata.test_source(key)
      send(pid, {:source_tested, key})
    end)

    {:noreply, update(socket, :testing, &MapSet.put(&1, key))}
  end

  # ── Settings ────────────────────────────────────────────────────────────────

  def handle_event("save_settings", %{"settings" => s}, socket) do
    value = %{
      "auto_match_threshold" => percent(s["auto_match_threshold"], 90),
      "auto_match_margin" => percent(s["auto_match_margin"], 10),
      "overwrite_mode" => if(s["overwrite_mode"] == "fill", do: "fill", else: "replace"),
      "write_to_files" => s["write_to_files"] == "true",
      "write_comicinfo" => s["write_comicinfo"] == "true"
    }

    {:ok, _} = Settings.put("metadata", value)
    {:noreply, socket |> assign(settings: Settings.metadata()) |> put_flash(:info, "Settings saved")}
  end

  # ── Review ──────────────────────────────────────────────────────────────────

  def handle_event("skip_review", %{"id" => id}, socket) do
    id |> Metadata.get_review!() |> Metadata.skip_review()
    {:noreply, load_reviews(socket)}
  end

  def handle_event("retry_review", %{"id" => id}, socket) do
    review = Metadata.get_review!(id)

    cond do
      review.book_id -> Metadata.enqueue_book(review.book_id)
      review.series_id -> Metadata.enqueue_series(review.series_id)
    end

    {:noreply, put_flash(socket, :info, "Queued for another automatic match")}
  end

  def handle_event("close_identify_dialog", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/metadata/review")}
  end

  # ── Jobs ────────────────────────────────────────────────────────────────────

  def handle_event("match_library", %{"id" => id, "all" => all}, socket) do
    {:ok, _} = Metadata.enqueue_library(id, skip_matched: all != "true")
    {:noreply, socket |> load_jobs() |> put_flash(:info, "Library queued for metadata matching")}
  end

  def handle_event("retry_failed", _params, socket) do
    Metadata.retry_failed_jobs()
    {:noreply, load_jobs(socket)}
  end

  def handle_event("cancel_pending", _params, socket) do
    Metadata.cancel_pending_jobs()
    {:noreply, load_jobs(socket)}
  end

  defp percent(v, default) do
    case Float.parse(to_string(v)) do
      {f, _} -> min(max(f, 0.0), 100.0) / 100
      :error -> default / 100
    end
  end

  @impl true
  def handle_info({:source_tested, key}, socket) do
    {:noreply, socket |> update(:testing, &MapSet.delete(&1, key)) |> load_sources()}
  end

  def handle_info({:metadata_event, _event}, socket) do
    socket =
      case socket.assigns.live_action do
        :metadata_review -> load_reviews(socket)
        _ -> assign(socket, review_count: Metadata.count_reviews())
      end

    {:noreply, socket}
  end

  def handle_info({:identify_applied, _kind, _id}, socket) do
    {:noreply, socket |> put_flash(:info, "Metadata applied") |> push_patch(to: ~p"/admin/metadata/review")}
  end

  def handle_info(:refresh_jobs, socket) do
    if socket.assigns.live_action == :metadata_jobs,
      do: {:noreply, load_jobs(socket)},
      else: {:noreply, assign(socket, refresh_timer: nil)}
  end

  # Scan progress from the sidebar hooks' subscriptions
  def handle_info({:scan_progress, _}, socket), do: {:noreply, socket}
  def handle_info({:book_added, _}, socket), do: {:noreply, socket}
  def handle_info({:cover_updated, _}, socket), do: {:noreply, socket}

  # ── Render ──────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-white">Metadata</h1>
      </div>

      <div class="flex gap-2 border-b border-gray-800 overflow-x-auto">
        <%= for {label, action, path} <- [
              {"Sources", :metadata_sources, ~p"/admin/metadata"},
              {"Settings", :metadata_settings, ~p"/admin/metadata/settings"},
              {"Review", :metadata_review, ~p"/admin/metadata/review"},
              {"Jobs", :metadata_jobs, ~p"/admin/metadata/jobs"}
            ] do %>
          <.link
            patch={path}
            class={[
              "px-4 py-2 text-sm font-medium -mb-px border-b-2 transition-colors flex items-center gap-2 whitespace-nowrap",
              if(@live_action == action,
                do: "border-violet-500 text-violet-400",
                else: "border-transparent text-gray-500 hover:text-gray-300"
              )
            ]}
          >
            {label}
            <%= if action == :metadata_review and @review_count > 0 do %>
              <span class="text-[10px] font-semibold px-1.5 py-0.5 rounded-full bg-amber-600/30 text-amber-300">
                {@review_count}
              </span>
            <% end %>
          </.link>
        <% end %>
      </div>

      <%= if @live_action == :metadata_sources do %>
        <.sources_tab sources={@sources} testing={@testing} />
      <% end %>

      <%= if @live_action == :metadata_settings do %>
        <.settings_tab settings={@settings} />
      <% end %>

      <%= if @live_action == :metadata_review do %>
        <.review_tab reviews={@reviews} />
        <%= if @identify_review do %>
          <.live_component
            module={StashixWeb.IdentifyComponent}
            id="identify-review"
            target={@identify_review.book || @identify_review.series}
            review={@identify_review}
          />
        <% end %>
      <% end %>

      <%= if @live_action == :metadata_jobs do %>
        <.jobs_tab job_counts={@job_counts} libraries={@libraries} />
      <% end %>
    </div>
    """
  end

  attr :sources, :list
  attr :testing, :any

  defp sources_tab(assigns) do
    ~H"""
    <div class="space-y-4 max-w-3xl">
      <p class="text-sm text-gray-500">
        Sources are searched in priority order when matching automatically. Credentials and cookies are stored encrypted.
      </p>

      <%= for {%{module: mod, config: row}, idx} <- Enum.with_index(@sources) do %>
        <% configured = Sources.configured?(mod, row.config)
        values = row.config || %{}
        {default_n, default_ms} = mod.default_rate_limit() %>
        <div class={[
          "rounded-xl border p-5 space-y-4",
          if(row.enabled, do: "border-violet-700/50 bg-gray-900", else: "border-gray-800 bg-gray-900/60")
        ]}>
          <div class="flex items-start gap-3">
            <div class="flex flex-col gap-1 pt-0.5">
              <button
                phx-click="move_source"
                phx-value-key={row.source_key}
                phx-value-dir="up"
                disabled={idx == 0}
                class="text-gray-500 hover:text-white disabled:opacity-30"
                title="Higher priority"
              >
                <.icon name="lucide-chevron-up" class="w-4 h-4" />
              </button>
              <button
                phx-click="move_source"
                phx-value-key={row.source_key}
                phx-value-dir="down"
                disabled={idx == length(@sources) - 1}
                class="text-gray-500 hover:text-white disabled:opacity-30"
                title="Lower priority"
              >
                <.icon name="lucide-chevron-down" class="w-4 h-4" />
              </button>
            </div>
            <div class="flex-1 min-w-0">
              <div class="flex flex-wrap items-center gap-2">
                <h2 class="text-base font-semibold text-white">{mod.name()}</h2>
                <a
                  href={mod.homepage()}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-gray-500 hover:text-gray-300"
                >
                  <.icon name="lucide-external-link" class="w-3.5 h-3.5" />
                </a>
                <%= if not configured do %>
                  <span class="text-[10px] px-1.5 py-0.5 rounded bg-amber-900/40 text-amber-300">
                    Needs configuration
                  </span>
                <% end %>
                <%= case row.last_test_status do %>
                  <% "ok" -> %>
                    <span
                      class="text-[10px] px-1.5 py-0.5 rounded bg-emerald-900/40 text-emerald-300"
                      title={to_string(row.last_tested_at)}
                    >
                      Connection OK
                    </span>
                  <% "error" -> %>
                    <span class="text-[10px] px-1.5 py-0.5 rounded bg-red-900/40 text-red-300" title={row.last_test_message}>
                      {row.last_test_message}
                    </span>
                  <% _ -> %>
                <% end %>
              </div>
              <p class="text-sm text-gray-500 mt-0.5">{mod.description()}</p>
            </div>
            <div class="flex flex-col items-end gap-2">
              <.source_toggle label="Enabled" on={row.enabled} key={row.source_key} field="enabled" />
              <.source_toggle label="Auto-apply" on={row.auto_apply} key={row.source_key} field="auto_apply" />
            </div>
          </div>

          <form phx-submit="save_source" class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <input type="hidden" name="key" value={row.source_key} />
            <%= for field <- mod.config_schema() do %>
              <% value = Map.get(values, field.key)
              has_value = value not in [nil, ""] %>
              <div class={if field.type == :cookies, do: "sm:col-span-2", else: ""}>
                <label class="block text-xs font-medium text-gray-400 mb-1.5">
                  {field.label}<span :if={Map.get(field, :required)} class="text-violet-400">*</span>
                </label>
                <%= case field.type do %>
                  <% :secret -> %>
                    <input
                      type="password"
                      name={"config[#{field.key}]"}
                      value=""
                      autocomplete="new-password"
                      placeholder={if has_value, do: "•••••••• saved — leave blank to keep", else: ""}
                      class={input_class()}
                    />
                  <% :cookies -> %>
                    <textarea
                      name={"config[#{field.key}]"}
                      rows="3"
                      placeholder={if has_value, do: "Cookies saved — leave blank to keep", else: "name=value; other=value"}
                      class={[input_class(), "font-mono text-xs"]}
                    ></textarea>
                  <% :boolean -> %>
                    <select name={"config[#{field.key}]"} class={input_class()}>
                      <option value="true" selected={value == true}>Yes</option>
                      <option value="false" selected={value != true}>No</option>
                    </select>
                  <% _ -> %>
                    <input
                      type={if field.type == :integer, do: "number", else: "text"}
                      name={"config[#{field.key}]"}
                      value={value}
                      class={input_class()}
                    />
                <% end %>
                <p :if={Map.get(field, :help)} class="text-xs text-gray-600 mt-1">{field.help}</p>
              </div>
            <% end %>
            <div>
              <label class="block text-xs font-medium text-gray-400 mb-1.5">Rate limit (requests / minute)</label>
              <input
                type="number"
                min="1"
                name="rate_limit_per_minute"
                value={row.rate_limit_per_minute}
                placeholder={"Default: #{Float.round(default_n * 60_000 / default_ms, 1)}"}
                class={input_class()}
              />
            </div>
            <div class="sm:col-span-2 flex justify-end gap-2">
              <button
                type="button"
                phx-click="test_source"
                phx-value-key={row.source_key}
                disabled={MapSet.member?(@testing, row.source_key)}
                class="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm rounded-lg border border-gray-700 bg-gray-800 hover:bg-gray-700 text-gray-300 disabled:opacity-60"
              >
                <%= if MapSet.member?(@testing, row.source_key) do %>
                  <.icon name="lucide-loader-circle" class="w-3.5 h-3.5 animate-spin" /> Testing…
                <% else %>
                  <.icon name="lucide-plug" class="w-3.5 h-3.5" /> Test connection
                <% end %>
              </button>
              <button
                type="submit"
                class="px-3 py-1.5 text-sm rounded-lg bg-violet-600 hover:bg-violet-500 text-white"
              >
                Save
              </button>
            </div>
          </form>
        </div>
      <% end %>
    </div>
    """
  end

  attr :label, :string
  attr :on, :boolean
  attr :key, :string
  attr :field, :string

  defp source_toggle(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="toggle_source"
      phx-value-key={@key}
      phx-value-field={@field}
      class="flex items-center gap-2 text-xs text-gray-400"
    >
      {@label}
      <span class={[
        "relative inline-flex h-5 w-9 items-center rounded-full transition-colors",
        if(@on, do: "bg-violet-600", else: "bg-gray-700")
      ]}>
        <span class={[
          "inline-block h-4 w-4 transform rounded-full bg-white transition-transform",
          if(@on, do: "translate-x-4", else: "translate-x-0.5")
        ]} />
      </span>
    </button>
    """
  end

  attr :settings, :map

  defp settings_tab(assigns) do
    ~H"""
    <form phx-submit="save_settings" class="max-w-xl space-y-5">
      <div class="grid grid-cols-2 gap-4">
        <div>
          <label class="block text-xs font-medium text-gray-400 mb-1.5">Auto-match threshold (%)</label>
          <input
            type="number"
            min="0"
            max="100"
            name="settings[auto_match_threshold]"
            value={round(@settings["auto_match_threshold"] * 100)}
            class={input_class()}
          />
          <p class="text-xs text-gray-600 mt-1">Minimum score to apply a match without review.</p>
        </div>
        <div>
          <label class="block text-xs font-medium text-gray-400 mb-1.5">Required lead (%)</label>
          <input
            type="number"
            min="0"
            max="100"
            name="settings[auto_match_margin]"
            value={round(@settings["auto_match_margin"] * 100)}
            class={input_class()}
          />
          <p class="text-xs text-gray-600 mt-1">How far ahead of the runner-up the best match must be.</p>
        </div>
      </div>

      <div>
        <label class="block text-xs font-medium text-gray-400 mb-1.5">When applying a match</label>
        <select name="settings[overwrite_mode]" class={input_class()}>
          <option value="replace" selected={@settings["overwrite_mode"] == "replace"}>
            Replace fields the source provides
          </option>
          <option value="fill" selected={@settings["overwrite_mode"] == "fill"}>
            Only fill empty fields
          </option>
        </select>
      </div>

      <div class="space-y-2">
        <input type="hidden" name="settings[write_to_files]" value="false" />
        <label class="flex items-start gap-2 text-sm text-gray-300">
          <input
            type="checkbox"
            name="settings[write_to_files]"
            value="true"
            checked={@settings["write_to_files"]}
            class="mt-0.5 rounded border-gray-600 bg-gray-800 text-violet-600"
          />
          <span>
            Write metadata to files
            <span class="block text-xs text-gray-500">
              CBZ files get MetronInfo.xml embedded; other formats get a <code>&lt;book name&gt;.xml</code> sidecar.
            </span>
          </span>
        </label>
        <input type="hidden" name="settings[write_comicinfo]" value="false" />
        <label class="flex items-start gap-2 text-sm text-gray-300">
          <input
            type="checkbox"
            name="settings[write_comicinfo]"
            value="true"
            checked={@settings["write_comicinfo"]}
            class="mt-0.5 rounded border-gray-600 bg-gray-800 text-violet-600"
          />
          <span>
            Also write ComicInfo.xml into CBZ files
            <span class="block text-xs text-gray-500">For readers that don't understand MetronInfo.</span>
          </span>
        </label>
      </div>

      <button type="submit" class="px-4 py-2 text-sm rounded-lg bg-violet-600 hover:bg-violet-500 text-white">
        Save settings
      </button>
    </form>
    """
  end

  attr :reviews, :list

  defp review_tab(assigns) do
    ~H"""
    <div class="space-y-3">
      <%= if @reviews == [] do %>
        <p class="text-sm text-gray-500 py-10 text-center">Nothing to review.</p>
      <% end %>
      <%= for review <- @reviews do %>
        <% top = List.first(review.candidates) %>
        <div class="flex items-center gap-4 rounded-xl border border-gray-800 bg-gray-900 px-4 py-3">
          <div class="w-10 aspect-[2/3] rounded bg-gray-800 overflow-hidden flex-shrink-0">
            <%= if review.book && review.book.cover do %>
              <img src={~p"/api/books/#{review.book.id}/cover?s=s"} alt="" class="w-full h-full object-cover" />
            <% end %>
          </div>
          <div class="min-w-0 flex-1">
            <%= if review.book do %>
              <.link navigate={~p"/book/#{review.book.id}"} class="text-sm text-white hover:underline truncate block">
                {(review.book.series && "#{review.book.series.name} ") || ""}{if review.book.issue_number,
                  do: "##{Stashix.Metadata.Matcher.format_number(review.book.issue_number)}",
                  else: review.book.title}
              </.link>
            <% else %>
              <.link navigate={~p"/series/#{review.series.id}"} class="text-sm text-white hover:underline truncate block">
                {review.series.name} <span class="text-xs text-gray-500">(series)</span>
              </.link>
            <% end %>
            <p class="text-xs text-gray-500 truncate">
              <%= cond do %>
                <% review.error -> %>
                  <span class="text-red-400">{review.error}</span>
                <% top -> %>
                  Best: {top["title"] || top["series_name"]} · {round((top["score"] || 0) * 100)}% · {length(
                    review.candidates
                  )} candidates
                <% true -> %>
                  No candidates found
              <% end %>
            </p>
          </div>
          <div class="flex gap-2 flex-shrink-0">
            <.link
              patch={~p"/admin/metadata/review?identify=#{review.id}"}
              class="px-3 py-1.5 text-sm rounded-lg bg-violet-600 hover:bg-violet-500 text-white"
            >
              Identify
            </.link>
            <button
              phx-click="retry_review"
              phx-value-id={review.id}
              class="px-3 py-1.5 text-sm rounded-lg border border-gray-700 bg-gray-800 hover:bg-gray-700 text-gray-300"
            >
              Retry
            </button>
            <button
              phx-click="skip_review"
              phx-value-id={review.id}
              class="px-3 py-1.5 text-sm rounded-lg border border-gray-700 bg-gray-800 hover:bg-gray-700 text-gray-400"
            >
              Skip
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :job_counts, :map
  attr :libraries, :list

  defp jobs_tab(assigns) do
    ~H"""
    <div class="space-y-8 max-w-3xl">
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <%= for {queue, label} <- [{"metadata", "Matching"}, {"metadata_write", "File writes"}] do %>
          <% counts = Map.get(@job_counts, queue, %{}) %>
          <div class="rounded-xl border border-gray-800 bg-gray-900 p-4">
            <h3 class="text-sm font-semibold text-white mb-3">{label}</h3>
            <dl class="grid grid-cols-3 gap-2 text-center">
              <%= for {state, name, color} <- [
                    {"available", "Queued", "text-gray-300"},
                    {"executing", "Running", "text-violet-300"},
                    {"scheduled", "Waiting", "text-gray-400"},
                    {"completed", "Done", "text-emerald-300"},
                    {"retryable", "Retrying", "text-amber-300"},
                    {"discarded", "Failed", "text-red-300"}
                  ] do %>
                <div class="rounded-lg bg-gray-800/50 py-2">
                  <dd class={["text-lg font-semibold", color]}>{Map.get(counts, state, 0)}</dd>
                  <dt class="text-[11px] text-gray-500">{name}</dt>
                </div>
              <% end %>
            </dl>
          </div>
        <% end %>
      </div>

      <div class="flex gap-2">
        <button
          phx-click="retry_failed"
          class="px-3 py-1.5 text-sm rounded-lg border border-gray-700 bg-gray-800 hover:bg-gray-700 text-gray-300"
        >
          Retry failed
        </button>
        <button
          phx-click="cancel_pending"
          class="px-3 py-1.5 text-sm rounded-lg border border-gray-700 bg-gray-800 hover:bg-gray-700 text-red-400"
        >
          Cancel queued
        </button>
      </div>

      <div class="space-y-3">
        <h2 class="text-base font-semibold text-white">Match a library</h2>
        <%= for lib <- @libraries do %>
          <div class="flex items-center justify-between rounded-xl border border-gray-800 bg-gray-900 px-4 py-3">
            <div>
              <p class="text-white text-sm font-medium">{lib.name}</p>
              <p class="text-gray-500 text-xs">{lib.root_path}</p>
            </div>
            <div class="flex gap-2">
              <button
                phx-click="match_library"
                phx-value-id={lib.id}
                phx-value-all="false"
                class="px-3 py-1.5 text-sm rounded-lg bg-violet-600 hover:bg-violet-500 text-white"
              >
                Match unmatched
              </button>
              <button
                phx-click="match_library"
                phx-value-id={lib.id}
                phx-value-all="true"
                class="px-3 py-1.5 text-sm rounded-lg border border-gray-700 bg-gray-800 hover:bg-gray-700 text-amber-400"
              >
                Re-match all
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp input_class,
    do:
      "w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 text-sm px-3 py-2 placeholder:text-gray-500 focus:outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500"
end
