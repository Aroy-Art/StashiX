defmodule StashixWeb.AdminHealthLive do
  use StashixWeb, :live_view

  import Ecto.Query

  alias Stashix.{Health, Library, Repo}
  alias Stashix.Health.Workers.{IntegrityLibraryWorker, UnsupportedFilesWorker}

  on_mount {StashixWeb.Live.Hooks, :require_admin}

  @impl true
  def mount(_params, _session, socket) do
    libraries = Library.list_libraries(%{role: :admin})

    summaries = Map.new(libraries, fn lib -> {lib.id, Health.library_summary(lib.id)} end)
    integrity_jobs = active_integrity_jobs()

    {:ok,
     assign(socket,
       admin_sidebar: true,
       libraries: libraries,
       summaries: summaries,
       integrity_jobs: integrity_jobs,
       active_section: nil,
       section_data: %{},
       page_title: "Admin · Health"
     )}
  end

  @impl true
  def handle_event("run_integrity", %{"library_id" => library_id}, socket) do
    Oban.insert(IntegrityLibraryWorker.new(%{library_id: library_id}))
    integrity_jobs = active_integrity_jobs()
    {:noreply, assign(socket, integrity_jobs: integrity_jobs)}
  end

  def handle_event("run_unsupported_scan", %{"library_id" => library_id}, socket) do
    Oban.insert(UnsupportedFilesWorker.new(%{library_id: library_id}))
    {:noreply, socket}
  end

  def handle_event("show_section", %{"library_id" => library_id, "section" => section}, socket) do
    section_atom = String.to_existing_atom(section)
    data = load_section(section_atom, library_id)

    {:noreply,
     assign(socket,
       active_section: {library_id, section_atom},
       section_data: Map.put(socket.assigns.section_data, {library_id, section_atom}, data)
     )}
  end

  def handle_event("hide_section", _params, socket) do
    {:noreply, assign(socket, active_section: nil)}
  end

  @impl true
  def handle_info({:integrity_started, _}, socket) do
    integrity_jobs = active_integrity_jobs()
    {:noreply, assign(socket, integrity_jobs: integrity_jobs)}
  end

  def handle_info({:integrity_file_done, %{library_id: library_id}}, socket) do
    case get_in(socket.assigns, [:sidebar_health_progress, library_id]) do
      %{done: true} ->
        summaries = refresh_summary(socket.assigns.summaries, library_id)
        integrity_jobs = active_integrity_jobs()

        section_data =
          maybe_refresh_section(
            socket.assigns.section_data,
            socket.assigns.active_section,
            library_id,
            :integrity_errors
          )

        {:noreply, assign(socket, summaries: summaries, integrity_jobs: integrity_jobs, section_data: section_data)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:integrity_cancelled, _}, socket) do
    {:noreply, assign(socket, integrity_jobs: active_integrity_jobs())}
  end

  def handle_info({:integrity_scan_complete, %{library_id: library_id}}, socket) do
    summaries = refresh_summary(socket.assigns.summaries, library_id)
    integrity_jobs = active_integrity_jobs()

    section_data =
      maybe_refresh_section(socket.assigns.section_data, socket.assigns.active_section, library_id, :integrity_errors)

    {:noreply, assign(socket, summaries: summaries, integrity_jobs: integrity_jobs, section_data: section_data)}
  end

  def handle_info({:unsupported_scan_done, %{}}, socket) do
    # Re-derive which library sent this by checking all summaries.
    summaries =
      Map.new(socket.assigns.libraries, fn lib ->
        {lib.id, Health.library_summary(lib.id)}
      end)

    section_data =
      Enum.reduce(socket.assigns.libraries, socket.assigns.section_data, fn lib, acc ->
        maybe_refresh_section(acc, socket.assigns.active_section, lib.id, :unsupported_files)
      end)

    {:noreply, assign(socket, summaries: summaries, section_data: section_data)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp load_section(:missing_files, library_id), do: Health.list_missing_files(library_id)
  defp load_section(:zero_page_books, library_id), do: Health.list_zero_page_books(library_id)
  defp load_section(:books_without_cover, library_id), do: Health.list_books_without_cover(library_id)
  defp load_section(:orphan_series, library_id), do: Health.list_orphan_series(library_id)
  defp load_section(:integrity_errors, library_id), do: Health.list_integrity_errors(library_id)
  defp load_section(:unsupported_files, library_id), do: Health.list_unsupported_files(library_id)

  defp active_integrity_jobs do
    from(j in Oban.Job,
      where:
        j.worker in [
          "Stashix.Health.Workers.IntegrityLibraryWorker",
          "Stashix.Health.Workers.IntegrityFileWorker"
        ] and j.state in ["available", "scheduled", "executing", "retryable"],
      select: fragment("?->>'library_id'", j.args),
      distinct: true
    )
    |> Repo.all()
    |> MapSet.new()
  rescue
    _ -> MapSet.new()
  end

  defp refresh_summary(summaries, library_id) do
    Map.put(summaries, library_id, Health.library_summary(library_id))
  end

  defp maybe_refresh_section(section_data, {lib_id, sec}, lib_id, sec) do
    Map.put(section_data, {lib_id, sec}, load_section(sec, lib_id))
  end

  defp maybe_refresh_section(section_data, _, _, _), do: section_data

  # ── Render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <.page wide>
      <div class="space-y-8">
        <.display_heading level={1} class="text-4xl!">Library Health</.display_heading>

        <div :for={lib <- @libraries} class="space-y-3">
          <% summary = Map.get(@summaries, lib.id, %{}) %>
          <% integrity_running = MapSet.member?(@integrity_jobs, lib.id) %>

          <div class="bg-gray-900 rounded-lg ring-1 ring-white/10 overflow-hidden">
            <%!-- Library header --%>
            <div class="p-4 border-b border-white/10 flex items-center justify-between">
              <div>
                <p class="text-white font-medium">{lib.name}</p>
                <p class="text-gray-400 text-sm">{lib.root_path}</p>
              </div>
              <div class="flex gap-2">
                <.ink_button
                  variant="ghost"
                  size="md"
                  phx-click="run_unsupported_scan"
                  phx-value-library_id={lib.id}
                >
                  Scan unsupported files
                </.ink_button>
                <.ink_button
                  variant="ghost"
                  size="md"
                  phx-click="run_integrity"
                  phx-value-library_id={lib.id}
                  disabled={integrity_running}
                >
                  <.icon :if={integrity_running} name="lucide-loader-circle" class="w-3.5 h-3.5 animate-spin" />
                  {if integrity_running, do: "Checking integrity…", else: "Check integrity"}
                </.ink_button>
              </div>
            </div>

            <%!-- Health metric grid --%>
            <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 divide-x divide-white/5">
              <.health_stat
                library_id={lib.id}
                section="missing_files"
                label="Missing files"
                count={Map.get(summary, :missing_files, 0)}
                active_section={@active_section}
              />
              <.health_stat
                library_id={lib.id}
                section="zero_page_books"
                label="Zero pages"
                count={Map.get(summary, :zero_page_books, 0)}
                active_section={@active_section}
              />
              <.health_stat
                library_id={lib.id}
                section="books_without_cover"
                label="No cover"
                count={Map.get(summary, :books_without_cover, 0)}
                active_section={@active_section}
              />
              <.health_stat
                library_id={lib.id}
                section="orphan_series"
                label="Orphan series"
                count={Map.get(summary, :orphan_series, 0)}
                active_section={@active_section}
              />
              <.health_stat
                library_id={lib.id}
                section="integrity_errors"
                label="Corrupt files"
                count={Map.get(summary, :integrity_errors, 0)}
                active_section={@active_section}
              />
              <.health_stat
                library_id={lib.id}
                section="unsupported_files"
                label="Unsupported"
                count={Map.get(summary, :unsupported_files, 0)}
                active_section={@active_section}
              />
            </div>

            <%!-- Expanded section detail --%>
            <% active_key = @active_section %>
            <%= if active_key && elem(active_key, 0) == lib.id do %>
              <% {_lib_id, section} = active_key %>
              <% data = Map.get(@section_data, active_key, []) %>
              <div class="border-t border-white/10 bg-gray-950 p-4 space-y-3">
                <div class="flex items-center justify-between">
                  <h3 class="text-sm font-bold tracking-widest uppercase text-gray-300">
                    {section_label(section)}
                  </h3>
                  <button
                    phx-click="hide_section"
                    class="text-gray-400 hover:text-white text-xs"
                  >
                    Close
                  </button>
                </div>
                <%= if data == [] do %>
                  <p class="text-gray-400 text-sm">All clear.</p>
                <% else %>
                  <.section_table section={section} data={data} />
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </.page>
    """
  end

  # ── Sub-components ────────────────────────────────────────────────────────

  attr :library_id, :string, required: true
  attr :section, :string, required: true
  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :active_section, :any, required: true

  defp health_stat(assigns) do
    ~H"""
    <% active = @active_section == {@library_id, String.to_atom(@section)} %>
    <button
      phx-click={if active, do: "hide_section", else: "show_section"}
      phx-value-library_id={@library_id}
      phx-value-section={@section}
      class={[
        "p-4 text-left transition-colors",
        if(active, do: "bg-gray-800", else: "hover:bg-gray-800/50"),
        if(@count > 0, do: "cursor-pointer", else: "cursor-default")
      ]}
    >
      <p class={["text-2xl font-black font-display", if(@count > 0, do: "text-red-400", else: "text-green-400")]}>
        {@count}
      </p>
      <p class="text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400 mt-0.5">{@label}</p>
    </button>
    """
  end

  attr :section, :atom, required: true
  attr :data, :list, required: true

  defp section_table(%{section: :missing_files} = assigns) do
    ~H"""
    <table class="w-full text-sm">
      <thead>
        <tr class="border-b border-white/10 text-left">
          <th class="pb-2 text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">Title</th>
          <th class="pb-2 text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">Path</th>
          <th class="pb-2 text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">Missing since</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @data} class="border-b border-white/5 last:border-0">
          <td class="py-2 pr-4 text-white">
            <.link navigate={~p"/book/#{row.book_id}"} class="hover:underline">{row.title}</.link>
          </td>
          <td class="py-2 pr-4 text-gray-400 font-mono text-xs truncate max-w-xs">{row.path}</td>
          <td class="py-2 text-gray-400 text-xs">{format_dt(row.deleted_at)}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp section_table(%{section: :zero_page_books} = assigns) do
    ~H"""
    <table class="w-full text-sm">
      <thead>
        <tr class="border-b border-white/10 text-left">
          <th class="pb-2 text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">Title</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @data} class="border-b border-white/5 last:border-0">
          <td class="py-2 text-white">
            <.link navigate={~p"/book/#{row.book_id}"} class="hover:underline">{row.title}</.link>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp section_table(%{section: :books_without_cover} = assigns) do
    ~H"""
    <table class="w-full text-sm">
      <thead>
        <tr class="border-b border-white/10 text-left">
          <th class="pb-2 text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">Title</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @data} class="border-b border-white/5 last:border-0">
          <td class="py-2 text-white">
            <.link navigate={~p"/book/#{row.book_id}"} class="hover:underline">{row.title}</.link>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp section_table(%{section: :orphan_series} = assigns) do
    ~H"""
    <table class="w-full text-sm">
      <thead>
        <tr class="border-b border-white/10 text-left">
          <th class="pb-2 text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">Series</th>
          <th class="pb-2 text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">Expected path</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @data} class="border-b border-white/5 last:border-0">
          <td class="py-2 pr-4 text-white">
            <.link navigate={~p"/series/#{row.series_id}"} class="hover:underline">{row.name}</.link>
          </td>
          <td class="py-2 text-gray-400 font-mono text-xs truncate max-w-sm">{row.path}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp section_table(%{section: :integrity_errors} = assigns) do
    ~H"""
    <div class="space-y-2">
      <div
        :for={row <- @data}
        class="rounded-md bg-gray-900 ring-1 ring-white/5 p-3 space-y-1"
      >
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <.link navigate={~p"/book/#{row.book_id}"} class="text-white font-medium hover:underline text-sm">
              {row.title}
            </.link>
            <details class="mt-0.5 group">
              <summary class="text-gray-400 font-mono text-xs cursor-pointer list-none hover:text-gray-200">
                {Path.basename(row.file_path)}
              </summary>
              <p class="text-gray-500 font-mono text-xs mt-1 break-all">{row.file_path}</p>
            </details>
          </div>
          <span class="text-gray-500 text-xs whitespace-nowrap shrink-0 pt-0.5">{format_dt(row.checked_at)}</span>
        </div>
        <div class="flex items-start gap-2 pt-1">
          <.icon name="lucide-triangle-alert" class="w-3.5 h-3.5 text-red-400 shrink-0 mt-0.5" />
          <div class="min-w-0">
            <p class="text-red-400 text-xs font-mono">{row.error_message}</p>
            <p :if={error_detail(row.error_message)} class="text-gray-400 text-xs mt-1">
              {error_detail(row.error_message)}
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp section_table(%{section: :unsupported_files} = assigns) do
    ~H"""
    <table class="w-full text-sm">
      <thead>
        <tr class="border-b border-white/10 text-left">
          <th class="pb-2 text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">File path</th>
          <th class="pb-2 text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">Extension</th>
          <th class="pb-2 text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">Scanned</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @data} class="border-b border-white/5 last:border-0">
          <td class="py-2 pr-4 text-gray-300 font-mono text-xs truncate max-w-sm">{row.file_path}</td>
          <td class="py-2 pr-4 text-yellow-400 text-xs font-mono">{Path.extname(row.file_path)}</td>
          <td class="py-2 text-gray-400 text-xs">{format_dt(row.checked_at)}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp section_label(:missing_files), do: "Missing files"
  defp section_label(:zero_page_books), do: "Books with zero pages"
  defp section_label(:books_without_cover), do: "Books without a cover"
  defp section_label(:orphan_series), do: "Orphaned series (folder gone)"
  defp section_label(:integrity_errors), do: "Corrupt or unreadable archives"
  defp section_label(:unsupported_files), do: "Unsupported file types"

  defp format_dt(nil), do: "—"
  defp format_dt(dt), do: NaiveDateTime.to_string(dt) |> String.slice(0, 16)

  defp error_detail("File not found on disk"),
    do:
      "The file was registered in the library but no longer exists at the expected path. Run a re-scan to remove or reassign it."

  defp error_detail("Archive contains no readable pages"),
    do:
      "The archive opened successfully but contains no image files. It may be empty or use an unsupported internal layout."

  defp error_detail("CRC mismatch" <> _),
    do:
      "One or more entries in the archive have a checksum mismatch, indicating file corruption. The download or copy may be incomplete."

  @eocd_detail "The ZIP's internal file table (End of Central Directory) is missing. The file was likely cut off during download or copy — re-downloading it usually fixes this."
  defp error_detail("Truncated ZIP" <> _), do: @eocd_detail
  defp error_detail(":bad_eocd"), do: @eocd_detail
  defp error_detail(":eocd_not_found"), do: @eocd_detail

  defp error_detail("Not a valid archive" <> _),
    do:
      "The file does not start with a valid ZIP, RAR, or 7-Zip signature. It may be mislabeled or have been truncated."

  defp error_detail("ZIP error: " <> detail), do: detail
  defp error_detail(_), do: nil
end
