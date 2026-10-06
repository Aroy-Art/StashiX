defmodule StashixWeb.AdminMetadataLive do
  @moduledoc "Admin · Metadata: source plugins, match settings, review queue and jobs."
  use StashixWeb, :live_view

  alias Stashix.{Library, Metadata, Settings}
  alias Stashix.Metadata.Sources
  import StashixWeb.DialogHistory

  on_mount {StashixWeb.Live.Hooks, :require_admin}

  @job_refresh_ms 3_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Metadata.subscribe_admin()

    {:ok,
     socket
     |> track_dialogs(~w(identify))
     |> assign(
       admin_sidebar: true,
       sources: [],
       testing: MapSet.new(),
       saved: MapSet.new(),
       cache_count: 0,
       settings: Settings.metadata(),
       reviews: [],
       review_count: Metadata.count_reviews(),
       identify_review: nil,
       job_counts: %{},
       libraries: [],
       summary_cleanup: nil,
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
    |> assign(
      page_title: "Admin · Metadata Jobs",
      libraries: Library.list_libraries(%{role: :admin}),
      summary_cleanup: nil
    )
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

    assign(socket, job_counts: Metadata.job_counts(), cache_count: Metadata.cache_count(), refresh_timer: timer)
  end

  defp source_row(socket, key), do: Enum.find(socket.assigns.sources, &(&1.config.source_key == key))

  # ── Sources ─────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("toggle_source", %{"key" => key, "field" => "enabled"}, socket) do
    %{config: row} = source_row(socket, key)

    case Sources.set_enabled(row, not row.enabled) do
      {:ok, _} ->
        {:noreply, load_sources(socket)}

      {:error, :untested} ->
        {:noreply, put_flash(socket, :error, "Test the connection successfully before enabling this source")}
    end
  end

  def handle_event("toggle_source", %{"key" => key, "field" => "auto_apply"}, socket) do
    %{config: row} = source_row(socket, key)
    {:ok, _} = Sources.update(row, %{"auto_apply" => not row.auto_apply})
    {:noreply, socket |> load_sources() |> mark_saved(key)}
  end

  def handle_event("move_source", %{"key" => key, "dir" => dir}, socket) do
    Sources.move(key, if(dir == "up", do: :up, else: :down))
    {:noreply, load_sources(socket)}
  end

  # Auto-saved on every (debounced) form change.
  def handle_event("autosave_source", %{"key" => key} = params, socket) do
    %{config: row} = source_row(socket, key)

    attrs = %{
      "config" => Map.get(params, "config", %{}),
      "rate_limit_per_minute" => pos_int(params["rate_limit_per_minute"]),
      "request_interval_ms" =>
        case Float.parse(params["request_interval_s"] || "") do
          {secs, _} when secs > 0 -> round(secs * 1000)
          _ -> nil
        end,
      "endpoint_limit_per_hour" => pos_int(params["endpoint_limit_per_hour"])
    }

    case Sources.update(row, attrs) do
      {:ok, updated} ->
        limits = [:rate_limit_per_minute, :request_interval_ms, :endpoint_limit_per_hour]

        if Map.take(updated, limits) != Map.take(row, limits),
          do: Stashix.Metadata.RateLimiter.reset(key)

        {:noreply, socket |> load_sources() |> mark_saved(key)}

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
      "write_comicinfo" => s["write_comicinfo"] == "true",
      "cache_search_hours" => non_neg(s["cache_search_hours"], 24),
      "cache_detail_days" => non_neg(s["cache_detail_days"], 30)
    }

    {:ok, _} = Settings.put("metadata", value)
    {:noreply, socket |> assign(settings: Settings.metadata()) |> mark_saved("settings")}
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
    {:noreply, close_dialog(socket, ~p"/admin/metadata/review")}
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

  def handle_event("clear_cache", _params, socket) do
    n = Metadata.clear_cache()
    images = Stashix.Metadata.ImageProxy.clear()
    {:noreply, socket |> load_jobs() |> put_flash(:info, "Cleared #{n} cached responses and #{images} images")}
  end

  def handle_event("cancel_pending", _params, socket) do
    Metadata.cancel_pending_jobs()
    {:noreply, load_jobs(socket)}
  end

  def handle_event("preview_summary_cleanup", _params, socket) do
    {:noreply, assign(socket, summary_cleanup: Metadata.summary_cleanup_preview())}
  end

  def handle_event("cancel_summary_cleanup", _params, socket) do
    {:noreply, assign(socket, summary_cleanup: nil)}
  end

  def handle_event("run_summary_cleanup", _params, socket) do
    %{books: books, series: series} = Metadata.clean_summaries()

    {:noreply,
     socket
     |> assign(summary_cleanup: nil)
     |> load_jobs()
     |> put_flash(:info, "Cleaned #{books} book and #{series} series summaries")}
  end

  defp mark_saved(socket, key) do
    Process.send_after(self(), {:clear_saved, key}, 2_000)
    update(socket, :saved, &MapSet.put(&1, key))
  end

  defp non_neg(v, default) do
    case Integer.parse(to_string(v)) do
      {n, _} when n >= 0 -> n
      _ -> default
    end
  end

  defp pos_int(v) do
    case Integer.parse(v || "") do
      {n, _} when n > 0 -> n
      _ -> nil
    end
  end

  defp percent(v, default) do
    case Float.parse(to_string(v)) do
      {f, _} -> min(max(f, 0.0), 100.0) / 100
      :error -> default / 100
    end
  end

  @impl true
  def handle_info({:clear_saved, key}, socket), do: {:noreply, update(socket, :saved, &MapSet.delete(&1, key))}

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
    {:noreply, socket |> put_flash(:info, "Metadata applied") |> close_dialog(~p"/admin/metadata/review")}
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
        <.sources_tab sources={@sources} testing={@testing} saved={@saved} />
      <% end %>

      <%= if @live_action == :metadata_settings do %>
        <.settings_tab settings={@settings} saved={MapSet.member?(@saved, "settings")} />
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
        <.jobs_tab
          job_counts={@job_counts}
          libraries={@libraries}
          cache_count={@cache_count}
          summary_cleanup={@summary_cleanup}
          write_to_files={@settings["write_to_files"]}
        />
      <% end %>
    </div>
    """
  end

  attr :sources, :list
  attr :testing, :any
  attr :saved, :any

  defp sources_tab(assigns) do
    ~H"""
    <div class="space-y-4 max-w-3xl">
      <p class="text-sm text-gray-500">
        Sources are searched in priority order when matching automatically. Changes save automatically; credentials and cookies are stored encrypted.
        A source can be enabled once its connection test succeeds.
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
              <.source_toggle
                label="Enabled"
                on={row.enabled}
                key={row.source_key}
                field="enabled"
                disabled={not row.enabled and row.last_test_status != "ok"}
                title={
                  if not row.enabled and row.last_test_status != "ok",
                    do: "Test the connection first"
                }
              />
              <.source_toggle label="Auto-apply" on={row.auto_apply} key={row.source_key} field="auto_apply" />
            </div>
          </div>

          <form
            id={"source-form-#{row.source_key}"}
            phx-change="autosave_source"
            phx-submit="autosave_source"
            class="grid grid-cols-1 sm:grid-cols-2 gap-3"
          >
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
                      phx-debounce="blur"
                      placeholder={if has_value, do: "•••••••• saved — leave blank to keep", else: ""}
                      class={input_class()}
                    />
                  <% :cookies -> %>
                    <textarea
                      name={"config[#{field.key}]"}
                      rows="3"
                      phx-debounce="blur"
                      placeholder={if has_value, do: "Cookies saved — leave blank to keep", else: "name=value; other=value"}
                      class={[input_class(), "font-mono text-xs"]}
                    ></textarea>
                  <% :boolean -> %>
                    <.ink_select
                      id={"config-#{mod.key()}-#{field.key}"}
                      name={"config[#{field.key}]"}
                      label={field.label}
                      variant="field"
                      value={to_string(value == true)}
                      options={[{"Yes", "true"}, {"No", "false"}]}
                    />
                  <% _ -> %>
                    <input
                      type={if field.type == :integer, do: "number", else: "text"}
                      name={"config[#{field.key}]"}
                      value={value}
                      phx-debounce="600"
                      class={input_class()}
                    />
                <% end %>
                <p :if={Map.get(field, :help)} class="text-xs text-gray-600 mt-1">{field.help}</p>
              </div>
            <% end %>
            <div :if={Sources.spaced?(mod)}>
              <label class="block text-xs font-medium text-gray-400 mb-1.5">Min. seconds between requests</label>
              <input
                type="number"
                min="0.1"
                step="0.1"
                name="request_interval_s"
                value={row.request_interval_ms && row.request_interval_ms / 1000}
                phx-debounce="600"
                placeholder={"Default: #{default_ms / 1000}"}
                class={input_class()}
              />
              <p class="text-xs text-gray-600 mt-1">Requests closer together than this risk a temporary block.</p>
            </div>
            <div :if={not Sources.spaced?(mod)}>
              <label class="block text-xs font-medium text-gray-400 mb-1.5">Rate limit (requests / minute)</label>
              <input
                type="number"
                min="1"
                name="rate_limit_per_minute"
                value={row.rate_limit_per_minute}
                phx-debounce="600"
                placeholder={"Default: #{Float.round(default_n * 60_000 / default_ms, 1)}"}
                class={input_class()}
              />
            </div>
            <div :if={Sources.endpoint_limits?(mod)}>
              <label class="block text-xs font-medium text-gray-400 mb-1.5">Requests per hour, per endpoint</label>
              <input
                type="number"
                min="1"
                name="endpoint_limit_per_hour"
                value={row.endpoint_limit_per_hour}
                phx-debounce="600"
                placeholder={"Default: #{mod.default_endpoint_limit_per_hour()}"}
                class={input_class()}
              />
              <p class="text-xs text-gray-600 mt-1">Each API endpoint (search, issues, issue, …) has its own quota.</p>
            </div>
            <div class="sm:col-span-2 flex items-center justify-end gap-3">
              <span
                :if={MapSet.member?(@saved, row.source_key)}
                class="inline-flex items-center gap-1 text-xs text-emerald-400"
              >
                <.icon name="lucide-check" class="w-3.5 h-3.5" /> Saved
              </span>
              <span :if={not row.enabled and row.last_test_status != "ok"} class="text-xs text-gray-500">
                Test the connection to enable
              </span>
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
  attr :disabled, :boolean, default: false
  attr :title, :string, default: nil

  defp source_toggle(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="toggle_source"
      phx-value-key={@key}
      phx-value-field={@field}
      disabled={@disabled}
      title={@title}
      class="flex items-center gap-2 text-xs text-gray-400 disabled:opacity-40 disabled:cursor-not-allowed"
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
  attr :saved, :boolean

  defp settings_tab(assigns) do
    ~H"""
    <form
      id="metadata-settings-form"
      phx-change="save_settings"
      phx-submit="save_settings"
      class="max-w-xl space-y-5"
    >
      <div class="grid grid-cols-2 gap-4">
        <div>
          <label class="block text-xs font-medium text-gray-400 mb-1.5">Auto-match threshold (%)</label>
          <input
            type="number"
            min="0"
            max="100"
            name="settings[auto_match_threshold]"
            phx-debounce="600"
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
            phx-debounce="600"
            value={round(@settings["auto_match_margin"] * 100)}
            class={input_class()}
          />
          <p class="text-xs text-gray-600 mt-1">How far ahead of the runner-up the best match must be.</p>
        </div>
      </div>

      <div>
        <label class="block text-xs font-medium text-gray-400 mb-1.5">When applying a match automatically</label>
        <.ink_select
          id="settings-overwrite-mode"
          name="settings[overwrite_mode]"
          label="When applying a match automatically"
          variant="field"
          value={@settings["overwrite_mode"]}
          options={[{"Only fill empty fields", "fill"}, {"Replace fields the source provides", "replace"}]}
        />
        <p class="text-xs text-gray-600 mt-1">
          In the Identify dialog you can pick exactly which fields to overwrite.
        </p>
      </div>

      <div class="grid grid-cols-2 gap-4">
        <div>
          <label class="block text-xs font-medium text-gray-400 mb-1.5">Cache searches (hours)</label>
          <input
            type="number"
            min="0"
            name="settings[cache_search_hours]"
            value={@settings["cache_search_hours"]}
            phx-debounce="600"
            class={input_class()}
          />
        </div>
        <div>
          <label class="block text-xs font-medium text-gray-400 mb-1.5">Cache issue/series details (days)</label>
          <input
            type="number"
            min="0"
            name="settings[cache_detail_days]"
            value={@settings["cache_detail_days"]}
            phx-debounce="600"
            class={input_class()}
          />
        </div>
        <p class="col-span-2 text-xs text-gray-600 -mt-2">
          Source responses are cached to save API requests. 0 disables caching.
        </p>
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

      <p class="h-5 text-xs text-emerald-400">
        <span :if={@saved} class="inline-flex items-center gap-1">
          <.icon name="lucide-check" class="w-3.5 h-3.5" /> Saved
        </span>
      </p>
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
            <%= if review.book && review.book.files != [] do %>
              <p class="text-[11px] text-gray-600 font-mono truncate mt-0.5">
                {review.book.library.name <>
                  "/" <> Path.relative_to(List.first(review.book.files).path, review.book.library.root_path)}
              </p>
            <% end %>
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
  attr :cache_count, :integer
  attr :summary_cleanup, :map
  attr :write_to_files, :boolean

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
        <button
          phx-click="clear_cache"
          class="ml-auto px-3 py-1.5 text-sm rounded-lg border border-gray-700 bg-gray-800 hover:bg-gray-700 text-gray-300"
          title="Delete cached source responses and images"
        >
          Clear cache ({@cache_count})
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

      <div class="space-y-3">
        <h2 class="text-base font-semibold text-white">Maintenance</h2>
        <div class="rounded-xl border border-gray-800 bg-gray-900 px-4 py-3 space-y-3">
          <div class="flex items-center justify-between gap-4">
            <div>
              <p class="text-white text-sm font-medium">Clean up summaries</p>
              <p class="text-gray-500 text-xs">
                Remove the "List of covers and their creators" table that older Comic Vine imports left at the end of summaries.
              </p>
            </div>
            <button
              :if={!@summary_cleanup}
              phx-click="preview_summary_cleanup"
              class="shrink-0 px-3 py-1.5 text-sm rounded-lg border border-gray-700 bg-gray-800 hover:bg-gray-700 text-gray-300"
            >
              Preview cleanup
            </button>
          </div>

          <div :if={@summary_cleanup} id="summary-cleanup-preview" class="space-y-3 border-t border-gray-800 pt-3">
            <%= if @summary_cleanup.books + @summary_cleanup.series == 0 do %>
              <p class="text-sm text-gray-400">Nothing to clean up. No summaries contain a cover table.</p>
              <button
                phx-click="cancel_summary_cleanup"
                class="px-3 py-1.5 text-sm rounded-lg border border-gray-700 bg-gray-800 hover:bg-gray-700 text-gray-300"
              >
                Close
              </button>
            <% else %>
              <p class="text-sm text-gray-300">
                This will rewrite the summary of <span class="font-semibold text-white">{@summary_cleanup.books}</span>
                books and <span class="font-semibold text-white">{@summary_cleanup.series}</span>
                series. Only the cover table at the end is removed; the rest of each summary is kept.
              </p>
              <p :if={@write_to_files and @summary_cleanup.books > 0} class="text-xs text-amber-400">
                Writing metadata to files is on, so {@summary_cleanup.books} file writes will be queued.
              </p>
              <p :if={!@write_to_files} class="text-xs text-gray-500">
                Writing metadata to files is off, so book files are not touched.
              </p>

              <div class="space-y-2">
                <%= for sample <- @summary_cleanup.samples do %>
                  <div class="rounded-lg bg-gray-800/50 p-3 text-xs space-y-1">
                    <p class="text-gray-400">
                      <span class="text-gray-500">{sample.kind}</span> · {sample.label || "Untitled"}
                    </p>
                    <p class="text-gray-300 line-clamp-2">
                      {if sample.kept == "", do: "(summary becomes empty)", else: sample.kept}
                    </p>
                    <p class="text-red-400 line-through line-clamp-3">{sample.removed}</p>
                  </div>
                <% end %>
                <p
                  :if={@summary_cleanup.books + @summary_cleanup.series > length(@summary_cleanup.samples)}
                  class="text-xs text-gray-500"
                >
                  Showing {length(@summary_cleanup.samples)} examples.
                </p>
              </div>

              <div class="flex gap-2">
                <button
                  phx-click="run_summary_cleanup"
                  class="px-3 py-1.5 text-sm rounded-lg bg-violet-600 hover:bg-violet-500 text-white"
                >
                  Clean {@summary_cleanup.books + @summary_cleanup.series} summaries
                </button>
                <button
                  phx-click="cancel_summary_cleanup"
                  class="px-3 py-1.5 text-sm rounded-lg border border-gray-700 bg-gray-800 hover:bg-gray-700 text-gray-300"
                >
                  Cancel
                </button>
              </div>
            <% end %>
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
