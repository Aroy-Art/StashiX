# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.SeriesEditComponent do
  @moduledoc """
  The series "Edit series metadata" dialog: every series field MetronInfo
  carries, in tabs, each with a lock (see `Stashix.Metadata.Locks`), plus the
  age-rating cascade to the series' issues.

  Sends `{:series_edit_saved, series_id}` to the parent LiveView.
  """
  use StashixWeb, :live_component

  import StashixWeb.MetadataEditComponents

  alias Stashix.{Library, Metadata, Repo}
  alias Stashix.Library.Series
  alias Stashix.Metadata.Locks

  @tabs [
    {"general", "General"},
    {"dates", "Years & counts"},
    {"names", "Names & publishing"},
    {"issues", "Issues"}
  ]

  @scalars ~w(name sort_name summary volume language format status start_year end_year ongoing issue_count volume_count)

  @age_ratings [
    {"Unknown", "unknown"},
    {"Everyone", "everyone"},
    {"Teen", "teen"},
    {"Teen+", "teen_plus"},
    {"Mature", "mature"},
    {"Adult", "adult"},
    {"Explicit", "explicit"}
  ]

  @impl true
  def update(%{series: series} = assigns, socket) do
    socket = assign(socket, Map.drop(assigns, [:series]))

    if socket.assigns[:series] && socket.assigns.series.id == series.id do
      {:ok, assign(socket, series: series)}
    else
      series = Repo.preload(series, [:alternative_names, :publishers])

      {:ok,
       assign(socket,
         series: series,
         draft: draft(series),
         locks: series.locked_fields || [],
         tab: "general",
         error: nil
       )}
    end
  end

  defp draft(series) do
    str = fn v -> if v == nil, do: "", else: to_string(v) end

    @scalars
    |> Map.new(&{&1, str.(Map.get(series, String.to_existing_atom(&1)))})
    |> Map.merge(%{
      "alternative_names" =>
        Enum.map(
          series.alternative_names,
          &%{"name" => &1.name, "lang" => &1.lang || "", "external_id" => &1.external_id}
        ),
      "publisher_ids" => series.publishers |> Enum.map(&(&1.canonical_publisher_id || &1.id)) |> Enum.uniq()
    })
  end

  ## Events

  @impl true
  def handle_event("change", %{"series" => params}, socket) do
    {:noreply, update(socket, :draft, &from_params(&1, params))}
  end

  def handle_event("tab", %{"tab" => tab}, socket), do: {:noreply, assign(socket, tab: tab)}

  def handle_event("toggle_lock", %{"field" => key}, socket) do
    locks = socket.assigns.locks
    locks = if key in locks, do: List.delete(locks, key), else: [key | locks]
    {:noreply, assign(socket, locks: Locks.clean(locks, Locks.series_keys()))}
  end

  def handle_event("item_remove", %{"field" => "alternative_names", "index" => index}, socket) do
    if "alternative_names" in socket.assigns.locks,
      do: {:noreply, socket},
      else:
        {:noreply,
         update(
           socket,
           :draft,
           &Map.update!(&1, "alternative_names", fn rows -> List.delete_at(rows, String.to_integer(index)) end)
         )}
  end

  def handle_event("row_add", %{"field" => "alternative_names"}, socket) do
    if "alternative_names" in socket.assigns.locks,
      do: {:noreply, socket},
      else:
        {:noreply,
         update(
           socket,
           :draft,
           &Map.update!(&1, "alternative_names", fn rows -> rows ++ [%{"name" => "", "lang" => "en"}] end)
         )}
  end

  def handle_event("save", %{"series" => params} = all, socket) do
    socket = update(socket, :draft, &from_params(&1, params))
    series = socket.assigns.series

    case save(series, socket.assigns.draft, socket.assigns.locks) do
      {:ok, updated} ->
        cascade_age_rating(series, all["age_rating"], all["age_rating_only_unknown"] == "true")
        send(self(), {:series_edit_saved, updated.id})
        {:noreply, socket}

      {:error, message} ->
        {:noreply, assign(socket, error: message)}
    end
  end

  defp from_params(draft, params) do
    scalars = for key <- @scalars, Map.has_key?(params, key), into: %{}, do: {key, params[key]}

    draft
    |> Map.merge(scalars)
    |> Map.put("alternative_names", indexed(params["alternative_names"]))
    |> Map.put("publisher_ids", params["publisher_ids"] || draft["publisher_ids"])
  end

  ## Saving

  defp save(series, draft, locks) do
    frozen? = fn key -> key in series.locked_fields and key in locks end

    attrs =
      for key <- @scalars, not frozen?.(key), into: %{} do
        {key, blank_to_nil(draft[key])}
      end
      |> Map.put("locked_fields", locks)
      |> then(&if frozen?.("publisher"), do: &1, else: Map.put(&1, "publisher_ids", draft["publisher_ids"] || []))

    Repo.transaction(fn ->
      with {:ok, updated} <- Library.update_series(series, attrs) do
        unless frozen?.("alternative_names") do
          names =
            for a <- draft["alternative_names"],
                name = blank_to_nil(a["name"]),
                name != nil,
                do: %{name: name, lang: blank_to_nil(a["lang"]) || "en", external_id: blank_to_nil(a["external_id"])}

          Library.replace_series_alternative_names(series.id, names)
        end

        updated
      else
        {:error, %Ecto.Changeset{} = cs} ->
          cs
          |> Ecto.Changeset.traverse_errors(fn {msg, _} -> msg end)
          |> Enum.map_join("; ", fn {f, m} -> "#{Phoenix.Naming.humanize(f)} #{Enum.join(m, ", ")}" end)
          |> Repo.rollback()
      end
    end)
  end

  defp cascade_age_rating(_series, rating, _only_unknown) when rating in [nil, ""], do: :ok

  defp cascade_age_rating(series, rating, only_unknown) do
    if rating != to_string(common_age_rating(series.books)) do
      with {:ok, ids} <- Library.set_series_age_rating(series.id, rating, only_unknown: only_unknown),
           true <- Stashix.Settings.metadata()["write_to_files"] do
        Enum.each(ids, &Metadata.enqueue_write/1)
      end
    end

    :ok
  end

  # The shared age rating of all issues, or nil when mixed/empty.
  defp common_age_rating(books) do
    case books |> Enum.map(& &1.age_rating) |> Enum.uniq() do
      [rating] -> rating
      _ -> nil
    end
  end

  ## Rendering

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        tabs: @tabs,
        age_ratings: @age_ratings,
        formats: Enum.map(Ecto.Enum.values(Series, :format), &{to_string(&1), to_string(&1)}),
        statuses: Enum.map(~w(Ongoing Completed Cancelled Hiatus), &{&1, &1}),
        current_rating: common_age_rating(assigns.series.books)
      )

    ~H"""
    <div>
      <.dialog id="edit-series-dialog" title="Edit series metadata" size="lg" on_close={JS.push("close_edit_dialog")}>
        <:description>
          Lock a field to keep rescans and metadata matching from changing it. The name, years and ongoing flag
          otherwise follow the folder name on every scan.
          <p :if={@folder} class="flex items-center gap-1.5 text-xs font-mono text-muted mt-1 break-all">
            <.icon name="lucide-folder" class="w-3 h-3 flex-shrink-0" />
            {@folder}
          </p>
        </:description>

        <.form for={%{}} as={:series} id="edit-series-form" phx-change="change" phx-submit="save" phx-target={@myself}>
          <.edit_tabs tabs={@tabs} current={@tab} target={@myself} />

          <.edit_panel tab="general" current={@tab}>
            <.edit_field label="Name" key="name" locks={@locks} target={@myself} class="col-span-2">
              <.edit_input name="series[name]" value={@draft["name"]} locked={"name" in @locks} />
            </.edit_field>
            <.edit_field label="Sort name" key="sort_name" locks={@locks} target={@myself} class="col-span-2">
              <.edit_input name="series[sort_name]" value={@draft["sort_name"]} locked={"sort_name" in @locks} />
            </.edit_field>
            <.edit_field label="Summary" key="summary" locks={@locks} target={@myself} class="col-span-2">
              <.edit_textarea name="series[summary]" rows="4" value={@draft["summary"]} locked={"summary" in @locks} />
            </.edit_field>
            <.edit_field label="Volume" key="volume" locks={@locks} target={@myself}>
              <.edit_input type="number" name="series[volume]" value={@draft["volume"]} locked={"volume" in @locks} />
            </.edit_field>
            <.edit_field label="Language" key="language" locks={@locks} target={@myself}>
              <.edit_language
                id="edit-series-language"
                name="series[language]"
                value={@draft["language"]}
                locked={"language" in @locks}
              />
              <.ink_button
                :if={@series.books != []}
                type="button"
                variant="ghost"
                size="md"
                class="mt-2"
                phx-click="open_push_language_dialog"
                phx-value-language={@draft["language"]}
              >
                <.icon name="lucide-arrow-down-to-line" class="w-3.5 h-3.5" /> Push to all issues…
              </.ink_button>
            </.edit_field>
            <.edit_field label="Format" key="format" locks={@locks} target={@myself}>
              <.edit_select
                name="series[format]"
                value={@draft["format"]}
                prompt="Unknown"
                options={@formats}
                locked={"format" in @locks}
              />
            </.edit_field>
            <.edit_field label="Status" key="status" locks={@locks} target={@myself}>
              <.edit_select
                name="series[status]"
                value={@draft["status"]}
                prompt="Unknown"
                options={@statuses}
                locked={"status" in @locks}
              />
            </.edit_field>
            <.edit_field
              label="Ongoing (from the folder name)"
              key="ongoing"
              locks={@locks}
              target={@myself}
              class="col-span-2"
            >
              <%= if "ongoing" in @locks do %>
                <input type="hidden" name="series[ongoing]" value={@draft["ongoing"]} />
                <p class="text-sm text-fg opacity-60">{if @draft["ongoing"] == "true", do: "Yes", else: "No"}</p>
              <% else %>
                <input type="hidden" name="series[ongoing]" value="false" />
                <label class="inline-flex items-center gap-2 text-sm text-fg-soft cursor-pointer">
                  <input
                    type="checkbox"
                    name="series[ongoing]"
                    value="true"
                    checked={@draft["ongoing"] == "true"}
                    class="ink-check"
                  /> Ongoing series
                </label>
              <% end %>
            </.edit_field>
          </.edit_panel>

          <.edit_panel tab="dates" current={@tab}>
            <.edit_field label="Start year" key="start_year" locks={@locks} target={@myself}>
              <.edit_input
                type="number"
                name="series[start_year]"
                value={@draft["start_year"]}
                locked={"start_year" in @locks}
              />
            </.edit_field>
            <.edit_field label="End year" key="end_year" locks={@locks} target={@myself}>
              <.edit_input type="number" name="series[end_year]" value={@draft["end_year"]} locked={"end_year" in @locks} />
            </.edit_field>
            <.edit_field label="Published issues" key="issue_count" locks={@locks} target={@myself}>
              <.edit_input
                type="number"
                min="0"
                name="series[issue_count]"
                value={@draft["issue_count"]}
                locked={"issue_count" in @locks}
              />
            </.edit_field>
            <.edit_field label="Volumes" key="volume_count" locks={@locks} target={@myself}>
              <.edit_input
                type="number"
                min="0"
                name="series[volume_count]"
                value={@draft["volume_count"]}
                locked={"volume_count" in @locks}
              />
            </.edit_field>
          </.edit_panel>

          <.edit_panel tab="names" current={@tab}>
            <.edit_field label="Also known as" key="alternative_names" locks={@locks} target={@myself} class="col-span-2">
              <% locked = "alternative_names" in @locks %>
              <.edit_rows
                :let={{row, i}}
                key="alternative_names"
                rows={@draft["alternative_names"]}
                locked={locked}
                target={@myself}
                add_label="Add name"
              >
                <input
                  :if={row["external_id"]}
                  type="hidden"
                  name={"series[alternative_names][#{i}][external_id]"}
                  value={row["external_id"]}
                />
                <.edit_input
                  name={"series[alternative_names][#{i}][name]"}
                  value={row["name"]}
                  locked={locked}
                  size="sm"
                  placeholder="Name"
                />
                <.edit_input
                  name={"series[alternative_names][#{i}][lang]"}
                  value={row["lang"]}
                  locked={locked}
                  size="sm"
                  placeholder="en"
                  class="!w-20"
                />
              </.edit_rows>
            </.edit_field>

            <.edit_field label="Publisher" key="publisher" locks={@locks} target={@myself} class="col-span-2">
              <%= if "publisher" in @locks do %>
                <input :for={id <- @draft["publisher_ids"]} type="hidden" name="series[publisher_ids][]" value={id} />
                <p class="text-sm text-fg opacity-60">
                  {@all_publishers
                  |> Enum.filter(&(&1.id in @draft["publisher_ids"]))
                  |> Enum.map_join(", ", & &1.name)
                  |> then(&if(&1 == "", do: "None", else: &1))}
                </p>
              <% else %>
                <div
                  id={"pub-picker-series-#{@series.id}"}
                  phx-hook="PublisherSearch"
                  phx-update="ignore"
                  class="relative"
                  data-publishers={Jason.encode!(Enum.map(@all_publishers, &%{id: &1.id, name: &1.name}))}
                  data-selected-ids={Jason.encode!(@draft["publisher_ids"])}
                  data-input-name="series[publisher_ids][]"
                >
                  <div class="pub-badges flex flex-wrap gap-1.5 mb-2" hidden></div>
                  <input
                    type="text"
                    placeholder="Search publishers…"
                    autocomplete="off"
                    form=""
                    class="w-full rounded-md bg-raised border border-line-strong text-fg text-sm px-3 py-2 placeholder:text-faint focus:outline-none focus:border-ink"
                  />
                </div>
                <.ink_button
                  type="button"
                  variant="ghost"
                  size="md"
                  class="mt-2"
                  id="push-publishers-btn"
                  phx-hook="PushPublishers"
                  data-picker-id={"pub-picker-series-#{@series.id}"}
                >
                  <.icon name="lucide-arrow-down-to-line" class="w-3.5 h-3.5" /> Push to all issues…
                </.ink_button>
              <% end %>
            </.edit_field>
          </.edit_panel>

          <.edit_panel tab="issues" current={@tab}>
            <div class="col-span-2">
              <.field label="Age rating of all issues">
                <.ink_select
                  id="edit-series-age-rating"
                  name="age_rating"
                  label="Age rating"
                  variant="field"
                  value={@current_rating}
                  prompt={if @series.books == [], do: "No issues", else: "Mixed — keep per-issue ratings"}
                  options={@age_ratings}
                />
              </.field>
              <% mixed = is_nil(@current_rating) && @series.books != [] %>
              <% unknown_count = Enum.count(@series.books, &(&1.age_rating in [:unknown, nil])) %>
              <div :if={mixed} class="mt-2">
                <.checkbox name="age_rating_only_unknown" unchecked_value="false" checked>
                  Only update issues rated Unknown ({unknown_count})
                </.checkbox>
              </div>
              <p class="flex items-start gap-1.5 text-xs text-warn/80 mt-1.5">
                <.icon name="lucide-triangle-alert" class="w-3.5 h-3.5 mt-px flex-shrink-0" />
                <%= if mixed do %>
                  Issues have different ratings. Unchecking the box above overwrites the age rating of all {length(
                    @series.books
                  )} issues.
                <% else %>
                  Changing this overwrites the age rating of all {length(@series.books)} issues in this series.
                <% end %>
              </p>
            </div>
          </.edit_panel>

          <p :if={@error} class="mt-4 text-sm font-medium text-danger">{@error}</p>

          <.dialog_footer>
            <.ink_button type="button" variant="ghost" size="md" phx-click="close_edit_dialog">Cancel</.ink_button>
            <.ink_button type="submit" size="md" phx-disable-with="Saving…">Save changes</.ink_button>
          </.dialog_footer>
        </.form>
      </.dialog>
    </div>
    """
  end
end
