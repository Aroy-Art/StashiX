# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.BookEditComponent do
  @moduledoc """
  The book "Edit metadata" dialog: every field MetronInfo / ComicInfo can
  carry, in tabs, each with a lock (see `Stashix.Metadata.Locks`).

  The draft lives here and follows the form's `phx-change`; saving writes the
  unlocked fields, the lock list, and queues a file write. Sends
  `{:book_edit_saved, book_id}` to the parent LiveView.
  """
  use StashixWeb, :live_component

  import StashixWeb.MetadataEditComponents

  alias Stashix.{Library, Metadata, Repo}
  alias Stashix.Library.{BookCredit, BookExternalId}
  alias Stashix.Metadata.{Importer, Locks, Record}

  @tabs [
    {"general", "General"},
    {"dates", "Dates & IDs"},
    {"people", "People"},
    {"story", "Story"},
    {"links", "Publishing & links"},
    {"extras", "ComicInfo extras"}
  ]

  @chip_keys ~w(genres tags stories characters teams locations reprints)

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
  def update(%{book: book} = assigns, socket) do
    socket = assign(socket, Map.drop(assigns, [:book]))

    # Only (re)build the draft when a different book comes in.
    if socket.assigns[:book] && socket.assigns.book.id == book.id do
      {:ok, socket}
    else
      book = Repo.preload(book, Record.preloads(), force: true)

      {:ok,
       assign(socket,
         book: book,
         draft: draft(book),
         locks: book.locked_fields || [],
         tab: "general",
         nonce: 0,
         error: nil
       )}
    end
  end

  defp draft(book) do
    str = fn v -> if v == nil, do: "", else: to_string(v) end

    scalars =
      for key <- Locks.book_scalars(), into: %{} do
        {key, str.(Map.get(book, String.to_existing_atom(key)))}
      end

    named = fn items -> Enum.map(items, &%{"name" => &1.name, "external_id" => Map.get(&1, :external_id)}) end

    Map.merge(scalars, %{
      "imprint" => (book.imprint && book.imprint.name) || "",
      "publisher_ids" => Enum.map(book.publishers, & &1.id),
      "genres" => named.(book.genres),
      "tags" => named.(book.tags),
      "stories" => named.(book.stories),
      "characters" => named.(book.characters),
      "teams" => named.(book.teams),
      "locations" => named.(book.locations),
      "reprints" => named.(book.reprints),
      "credits" =>
        book.credits
        |> Enum.sort_by(&{&1.creator.name, to_string(&1.role)})
        |> Enum.map(&%{"creator" => &1.creator.name, "role" => to_string(&1.role)}),
      "arcs" =>
        Enum.map(
          book.story_arcs,
          &%{"name" => &1.name, "arc_number" => str.(&1.arc_number), "external_id" => &1.external_id}
        ),
      "universes" =>
        Enum.map(
          book.universes,
          &%{"name" => &1.name, "designation" => str.(&1.designation), "external_id" => &1.external_id}
        ),
      "urls" => Enum.map(book.urls, &%{"url" => &1.url, "is_primary" => to_string(&1.is_primary)}),
      "prices" => Enum.map(book.prices, &%{"amount" => str.(&1.amount), "country" => &1.country}),
      "external_ids" =>
        Enum.map(
          book.external_ids,
          &%{"source" => to_string(&1.source), "source_id" => &1.source_id, "is_primary" => to_string(&1.is_primary)}
        )
    })
  end

  @row_templates %{
    "credits" => %{"creator" => "", "role" => "Writer"},
    "arcs" => %{"name" => "", "arc_number" => "", "external_id" => nil},
    "universes" => %{"name" => "", "designation" => "", "external_id" => nil},
    "urls" => %{"url" => "", "is_primary" => "false"},
    "prices" => %{"amount" => "", "country" => ""},
    "external_ids" => %{"source" => "Metron", "source_id" => "", "is_primary" => "false"}
  }

  ## Events

  @impl true
  def handle_event("change", %{"book" => params}, socket) do
    {:noreply, update(socket, :draft, &from_params(&1, params))}
  end

  def handle_event("tab", %{"tab" => tab}, socket), do: {:noreply, assign(socket, tab: tab)}

  def handle_event("toggle_lock", %{"field" => key}, socket) do
    locks = socket.assigns.locks
    locks = if key in locks, do: List.delete(locks, key), else: [key | locks]
    {:noreply, assign(socket, locks: Locks.clean(locks, Locks.book_keys()))}
  end

  def handle_event("chip_add", %{"field" => key, "value" => value}, socket) when key in @chip_keys do
    name = String.trim(value)

    socket =
      if name == "" or key in socket.assigns.locks or Enum.any?(socket.assigns.draft[key], &(&1["name"] == name)),
        do: socket,
        else: update(socket, :draft, &Map.update!(&1, key, fn items -> items ++ [%{"name" => name}] end))

    {:noreply, update(socket, :nonce, &(&1 + 1))}
  end

  def handle_event("item_remove", %{"field" => key, "index" => index}, socket) do
    if key in socket.assigns.locks do
      {:noreply, socket}
    else
      {:noreply,
       update(socket, :draft, &Map.update!(&1, key, fn items -> List.delete_at(items, String.to_integer(index)) end))}
    end
  end

  def handle_event("row_add", %{"field" => key}, socket) when is_map_key(@row_templates, key) do
    if key in socket.assigns.locks do
      {:noreply, socket}
    else
      {:noreply, update(socket, :draft, &Map.update!(&1, key, fn rows -> rows ++ [@row_templates[key]] end))}
    end
  end

  def handle_event("save", %{"book" => params}, socket) do
    socket = update(socket, :draft, &from_params(&1, params))

    case save(socket.assigns.book, socket.assigns.draft, socket.assigns.locks) do
      {:ok, book} ->
        Metadata.enqueue_write(book.id)
        send(self(), {:book_edit_saved, book.id})
        {:noreply, socket}

      {:error, message} ->
        {:noreply, assign(socket, error: message)}
    end
  end

  # The form carries the whole draft; chips and rows come back indexed.
  defp from_params(draft, params) do
    scalars =
      for key <- Locks.book_scalars() ++ ["imprint"], Map.has_key?(params, key), into: %{}, do: {key, params[key]}

    lists =
      for key <- @chip_keys ++ Map.keys(@row_templates), into: %{} do
        {key, indexed(params[key])}
      end

    draft
    |> Map.merge(scalars)
    |> Map.merge(lists)
    |> Map.put("publisher_ids", params["publisher_ids"] || draft["publisher_ids"])
  end

  ## Saving

  defp save(book, draft, locks) do
    # A field locked before the dialog opened and still locked stays as stored.
    frozen? = fn key -> key in book.locked_fields and key in locks end

    attrs =
      for key <- Locks.book_scalars(), not frozen?.(key), into: %{} do
        {key, blank_to_nil(draft[key])}
      end
      |> Map.put("locked_fields", locks)
      |> then(&if frozen?.("publisher"), do: &1, else: Map.put(&1, "publisher_ids", draft["publisher_ids"] || []))

    Repo.transaction(fn ->
      with {:ok, attrs} <- put_imprint(attrs, draft, frozen?),
           {:ok, updated} <- Library.update_book(book, attrs),
           children = children(draft, frozen?),
           {:ok, _} <- Importer.replace_book_metadata(updated, children, only_present: true) do
        updated
      else
        {:error, %Ecto.Changeset{} = cs} -> Repo.rollback(changeset_message(cs))
        {:error, reason} -> Repo.rollback(to_string(reason))
      end
    end)
  end

  defp put_imprint(attrs, draft, frozen?) do
    cond do
      frozen?.("imprint") ->
        {:ok, attrs}

      blank_to_nil(draft["imprint"]) == nil ->
        {:ok, Map.put(attrs, "imprint_id", nil)}

      true ->
        case publisher_name(draft["publisher_ids"]) do
          nil ->
            {:error, "An imprint needs a publisher"}

          publisher ->
            with {:ok, imprint} <- Library.get_or_create_imprint(publisher, String.trim(draft["imprint"])),
                 do: {:ok, Map.put(attrs, "imprint_id", imprint.id)}
        end
    end
  end

  defp publisher_name(ids) do
    case Enum.reject(ids || [], &(&1 in [nil, ""])) do
      [id | _] -> Library.get_publisher(id) |> then(&(&1 && &1.name))
      [] -> nil
    end
  end

  defp children(draft, frozen?) do
    names = fn key -> draft[key] |> Enum.map(&blank_to_nil(&1["name"])) |> Enum.reject(&is_nil/1) |> Enum.uniq() end

    resources = fn key ->
      draft[key]
      |> Enum.flat_map(fn i ->
        case blank_to_nil(i["name"]) do
          nil -> []
          name -> [%{name: name, external_id: blank_to_nil(i["external_id"])}]
        end
      end)
      |> Enum.uniq_by(& &1.name)
    end

    %{
      genres: names.("genres"),
      tags: names.("tags"),
      stories: resources.("stories"),
      characters: resources.("characters"),
      teams: resources.("teams"),
      locations: resources.("locations"),
      reprints: resources.("reprints"),
      credits: credits(draft["credits"]),
      arcs:
        for(
          a <- draft["arcs"],
          name = blank_to_nil(a["name"]),
          name != nil,
          do: %{name: name, arc_number: int(a["arc_number"]), external_id: blank_to_nil(a["external_id"])}
        ),
      universes:
        for(
          u <- draft["universes"],
          name = blank_to_nil(u["name"]),
          name != nil,
          do: %{name: name, designation: blank_to_nil(u["designation"]), external_id: blank_to_nil(u["external_id"])}
        ),
      urls:
        for(
          u <- draft["urls"],
          url = blank_to_nil(u["url"]),
          url != nil,
          do: %{url: url, is_primary: u["is_primary"] == "true"}
        ),
      prices:
        for(
          p <- draft["prices"],
          amount = decimal(p["amount"]),
          country = blank_to_nil(p["country"]),
          amount != nil and country != nil,
          do: %{amount: amount, country: String.upcase(country)}
        ),
      external_ids:
        for(
          e <- draft["external_ids"],
          id = blank_to_nil(e["source_id"]),
          id != nil,
          do: %{source: e["source"], source_id: id, is_primary: e["is_primary"] == "true"}
        )
    }
    |> Map.reject(fn {key, _} -> frozen?.(Atom.to_string(key)) end)
  end

  defp credits(rows) do
    rows
    |> Enum.flat_map(fn r ->
      case blank_to_nil(r["creator"]) do
        nil -> []
        creator -> [{creator, r["role"]}]
      end
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {creator, roles} -> %{creator: creator, roles: Enum.uniq(roles)} end)
  end

  defp int(s) do
    case Integer.parse(to_string(s || "")) do
      {n, _} when n > 0 -> n
      _ -> nil
    end
  end

  defp decimal(s) do
    case Decimal.parse(to_string(s || "")) do
      {d, _} -> d
      :error -> nil
    end
  end

  defp changeset_message(cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, _} -> msg end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{Phoenix.Naming.humanize(field)} #{Enum.join(msgs, ", ")}" end)
  end

  ## Rendering

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        tabs: @tabs,
        age_ratings: @age_ratings,
        roles: Enum.map(Ecto.Enum.values(BookCredit, :role), &{to_string(&1), to_string(&1)}),
        sources:
          BookExternalId
          |> Ecto.Enum.values(:source)
          |> List.delete(:Unknown)
          |> Enum.map(&{to_string(&1), to_string(&1)})
      )

    ~H"""
    <div>
      <.dialog id="edit-metadata-dialog" title="Edit metadata" size="lg" on_close={JS.push("close_edit_dialog")}>
        <:description>
          Lock a field to keep rescans and metadata matching from changing it. Saving also writes the metadata to the
          book's files.
          <p :if={@file_path} class="flex items-center gap-1.5 text-xs font-mono text-muted mt-1 break-all">
            <.icon name="lucide-file" class="w-3 h-3 flex-shrink-0" />
            {@file_path}
          </p>
        </:description>

        <.form for={%{}} as={:book} id="edit-book-form" phx-change="change" phx-submit="save" phx-target={@myself}>
          <.edit_tabs tabs={@tabs} current={@tab} target={@myself} />

          <%!-- General --%>
          <.edit_panel tab="general" current={@tab}>
            <.edit_field label="Title" key="title" locks={@locks} target={@myself} class="col-span-2">
              <.edit_input name="book[title]" value={@draft["title"]} locked={"title" in @locks} />
            </.edit_field>
            <.edit_field label="Issue #" key="issue_number" locks={@locks} target={@myself}>
              <.edit_input name="book[issue_number]" value={@draft["issue_number"]} locked={"issue_number" in @locks} />
            </.edit_field>
            <.edit_field label="Alternative #" key="alternative_number" locks={@locks} target={@myself}>
              <.edit_input
                name="book[alternative_number]"
                value={@draft["alternative_number"]}
                locked={"alternative_number" in @locks}
              />
            </.edit_field>
            <.edit_field label="Volume" key="volume" locks={@locks} target={@myself}>
              <.edit_input type="number" name="book[volume]" value={@draft["volume"]} locked={"volume" in @locks} />
            </.edit_field>
            <.edit_field label="Year" key="year" locks={@locks} target={@myself}>
              <.edit_input type="number" name="book[year]" value={@draft["year"]} locked={"year" in @locks} />
            </.edit_field>
            <.edit_field label="Language" key="language" locks={@locks} target={@myself}>
              <.edit_language
                id="edit-book-language"
                name="book[language]"
                value={@draft["language"]}
                locked={"language" in @locks}
              />
            </.edit_field>
            <.edit_field label="Age rating" key="age_rating" locks={@locks} target={@myself}>
              <.edit_select
                name="book[age_rating]"
                value={@draft["age_rating"]}
                options={@age_ratings}
                locked={"age_rating" in @locks}
              />
            </.edit_field>
            <.edit_field label="Collection title" key="collection_title" locks={@locks} target={@myself}>
              <.edit_input
                name="book[collection_title]"
                value={@draft["collection_title"]}
                locked={"collection_title" in @locks}
              />
            </.edit_field>
            <.edit_field label="Manga volume" key="manga_volume" locks={@locks} target={@myself}>
              <.edit_input name="book[manga_volume]" value={@draft["manga_volume"]} locked={"manga_volume" in @locks} />
            </.edit_field>
            <.edit_field label="Summary" key="summary" locks={@locks} target={@myself} class="col-span-2">
              <.edit_textarea name="book[summary]" rows="5" value={@draft["summary"]} locked={"summary" in @locks} />
            </.edit_field>
            <.edit_field label="Notes" key="notes" locks={@locks} target={@myself} class="col-span-2">
              <.edit_textarea name="book[notes]" value={@draft["notes"]} locked={"notes" in @locks} />
            </.edit_field>
          </.edit_panel>

          <%!-- Dates & IDs --%>
          <.edit_panel tab="dates" current={@tab}>
            <.edit_field label="Cover date" key="cover_date" locks={@locks} target={@myself}>
              <.edit_input type="date" name="book[cover_date]" value={@draft["cover_date"]} locked={"cover_date" in @locks} />
            </.edit_field>
            <.edit_field label="Store date" key="store_date" locks={@locks} target={@myself}>
              <.edit_input type="date" name="book[store_date]" value={@draft["store_date"]} locked={"store_date" in @locks} />
            </.edit_field>
            <.edit_field label="ISBN" key="isbn" locks={@locks} target={@myself}>
              <.edit_input name="book[isbn]" value={@draft["isbn"]} locked={"isbn" in @locks} />
            </.edit_field>
            <.edit_field label="UPC" key="upc" locks={@locks} target={@myself}>
              <.edit_input name="book[upc]" value={@draft["upc"]} locked={"upc" in @locks} />
            </.edit_field>
            <.edit_field label="Community rating (0–5)" key="community_rating" locks={@locks} target={@myself}>
              <.edit_input
                type="number"
                step="0.1"
                min="0"
                max="5"
                name="book[community_rating]"
                value={@draft["community_rating"]}
                locked={"community_rating" in @locks}
              />
            </.edit_field>
            <.edit_field label="Rating count" key="community_rating_count" locks={@locks} target={@myself}>
              <.edit_input
                type="number"
                min="0"
                name="book[community_rating_count]"
                value={@draft["community_rating_count"]}
                locked={"community_rating_count" in @locks}
              />
            </.edit_field>
            <.edit_field label="Source IDs" key="external_ids" locks={@locks} target={@myself} class="col-span-2">
              <% locked = "external_ids" in @locks %>
              <.edit_rows
                :let={{row, i}}
                key="external_ids"
                rows={@draft["external_ids"]}
                locked={locked}
                target={@myself}
                add_label="Add ID"
              >
                <.edit_select
                  name={"book[external_ids][#{i}][source]"}
                  value={row["source"]}
                  options={@sources}
                  locked={locked}
                  size="sm"
                  class="!w-44"
                />
                <.edit_input
                  name={"book[external_ids][#{i}][source_id]"}
                  value={row["source_id"]}
                  locked={locked}
                  size="sm"
                  placeholder="ID"
                />
                <.primary_flag name={"book[external_ids][#{i}][is_primary]"} value={row["is_primary"]} locked={locked} />
              </.edit_rows>
            </.edit_field>
          </.edit_panel>

          <%!-- People --%>
          <.edit_panel tab="people" current={@tab}>
            <.edit_field label="Credits" key="credits" locks={@locks} target={@myself} class="col-span-2">
              <% locked = "credits" in @locks %>
              <.edit_rows
                :let={{row, i}}
                key="credits"
                rows={@draft["credits"]}
                locked={locked}
                target={@myself}
                add_label="Add credit"
              >
                <.edit_input
                  name={"book[credits][#{i}][creator]"}
                  value={row["creator"]}
                  locked={locked}
                  size="sm"
                  placeholder="Creator"
                />
                <.edit_select
                  name={"book[credits][#{i}][role]"}
                  value={row["role"]}
                  options={@roles}
                  locked={locked}
                  size="sm"
                  class="!w-48"
                />
              </.edit_rows>
            </.edit_field>
            <.chip_field
              :for={{key, label} <- [{"characters", "Characters"}, {"teams", "Teams"}, {"locations", "Locations"}]}
              key={key}
              label={label}
              draft={@draft}
              locks={@locks}
              nonce={@nonce}
              target={@myself}
            />
            <.edit_field label="Universes" key="universes" locks={@locks} target={@myself} class="col-span-2">
              <% locked = "universes" in @locks %>
              <.edit_rows
                :let={{row, i}}
                key="universes"
                rows={@draft["universes"]}
                locked={locked}
                target={@myself}
                add_label="Add universe"
              >
                <input
                  :if={row["external_id"]}
                  type="hidden"
                  name={"book[universes][#{i}][external_id]"}
                  value={row["external_id"]}
                />
                <.edit_input
                  name={"book[universes][#{i}][name]"}
                  value={row["name"]}
                  locked={locked}
                  size="sm"
                  placeholder="Name"
                />
                <.edit_input
                  name={"book[universes][#{i}][designation]"}
                  value={row["designation"]}
                  locked={locked}
                  size="sm"
                  placeholder="Designation"
                />
              </.edit_rows>
            </.edit_field>
          </.edit_panel>

          <%!-- Story --%>
          <.edit_panel tab="story" current={@tab}>
            <.chip_field
              key="stories"
              label="Stories (first is the title in MetronInfo)"
              draft={@draft}
              locks={@locks}
              nonce={@nonce}
              target={@myself}
            />
            <.edit_field label="Story arcs" key="arcs" locks={@locks} target={@myself} class="col-span-2">
              <% locked = "arcs" in @locks %>
              <.edit_rows
                :let={{row, i}}
                key="arcs"
                rows={@draft["arcs"]}
                locked={locked}
                target={@myself}
                add_label="Add arc"
              >
                <input
                  :if={row["external_id"]}
                  type="hidden"
                  name={"book[arcs][#{i}][external_id]"}
                  value={row["external_id"]}
                />
                <.edit_input
                  name={"book[arcs][#{i}][name]"}
                  value={row["name"]}
                  locked={locked}
                  size="sm"
                  placeholder="Arc"
                />
                <.edit_input
                  type="number"
                  min="1"
                  name={"book[arcs][#{i}][arc_number]"}
                  value={row["arc_number"]}
                  locked={locked}
                  size="sm"
                  placeholder="#"
                  class="!w-20"
                />
              </.edit_rows>
            </.edit_field>
            <.chip_field
              :for={{key, label} <- [{"genres", "Genres"}, {"tags", "Tags"}, {"reprints", "Reprints"}]}
              key={key}
              label={label}
              draft={@draft}
              locks={@locks}
              nonce={@nonce}
              target={@myself}
            />
          </.edit_panel>

          <%!-- Publishing & links --%>
          <.edit_panel tab="links" current={@tab}>
            <.edit_field label="Publisher" key="publisher" locks={@locks} target={@myself} class="col-span-2">
              <%= if "publisher" in @locks do %>
                <input :for={id <- @draft["publisher_ids"]} type="hidden" name="book[publisher_ids][]" value={id} />
                <p class="text-sm text-fg opacity-60">
                  {@all_publishers
                  |> Enum.filter(&(&1.id in @draft["publisher_ids"]))
                  |> Enum.map_join(", ", & &1.name)
                  |> then(&if(&1 == "", do: "None", else: &1))}
                </p>
              <% else %>
                <div
                  id={"pub-picker-book-#{@book.id}"}
                  phx-hook="PublisherSearch"
                  phx-update="ignore"
                  class="relative"
                  data-publishers={Jason.encode!(Enum.map(@all_publishers, &%{id: &1.id, name: &1.name}))}
                  data-selected-ids={Jason.encode!(@draft["publisher_ids"])}
                  data-input-name="book[publisher_ids][]"
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
              <% end %>
            </.edit_field>
            <.edit_field
              label="Imprint"
              key="imprint"
              locks={@locks}
              target={@myself}
              hint="Belongs to the first publisher."
            >
              <.edit_input name="book[imprint]" value={@draft["imprint"]} locked={"imprint" in @locks} />
            </.edit_field>
            <div></div>
            <.edit_field label="Links" key="urls" locks={@locks} target={@myself} class="col-span-2">
              <% locked = "urls" in @locks %>
              <.edit_rows
                :let={{row, i}}
                key="urls"
                rows={@draft["urls"]}
                locked={locked}
                target={@myself}
                add_label="Add link"
              >
                <.edit_input
                  type="url"
                  name={"book[urls][#{i}][url]"}
                  value={row["url"]}
                  locked={locked}
                  size="sm"
                  placeholder="https://…"
                />
                <.primary_flag name={"book[urls][#{i}][is_primary]"} value={row["is_primary"]} locked={locked} />
              </.edit_rows>
            </.edit_field>
            <.edit_field label="Prices" key="prices" locks={@locks} target={@myself} class="col-span-2">
              <% locked = "prices" in @locks %>
              <.edit_rows
                :let={{row, i}}
                key="prices"
                rows={@draft["prices"]}
                locked={locked}
                target={@myself}
                add_label="Add price"
              >
                <.edit_input
                  type="number"
                  step="0.01"
                  min="0"
                  name={"book[prices][#{i}][amount]"}
                  value={row["amount"]}
                  locked={locked}
                  size="sm"
                  placeholder="Amount"
                />
                <.edit_input
                  name={"book[prices][#{i}][country]"}
                  value={row["country"]}
                  locked={locked}
                  size="sm"
                  placeholder="US"
                  class="!w-20 uppercase"
                />
              </.edit_rows>
            </.edit_field>
          </.edit_panel>

          <%!-- ComicInfo extras --%>
          <.edit_panel tab="extras" current={@tab}>
            <.edit_field label="Alternate series" key="alternate_series" locks={@locks} target={@myself}>
              <.edit_input
                name="book[alternate_series]"
                value={@draft["alternate_series"]}
                locked={"alternate_series" in @locks}
              />
            </.edit_field>
            <.edit_field label="Alternate count" key="alternate_count" locks={@locks} target={@myself}>
              <.edit_input
                type="number"
                min="1"
                name="book[alternate_count]"
                value={@draft["alternate_count"]}
                locked={"alternate_count" in @locks}
              />
            </.edit_field>
            <.edit_field label="Series group" key="series_group" locks={@locks} target={@myself}>
              <.edit_input name="book[series_group]" value={@draft["series_group"]} locked={"series_group" in @locks} />
            </.edit_field>
            <.edit_field label="Main character or team" key="main_character_or_team" locks={@locks} target={@myself}>
              <.edit_input
                name="book[main_character_or_team]"
                value={@draft["main_character_or_team"]}
                locked={"main_character_or_team" in @locks}
              />
            </.edit_field>
            <.edit_field label="Manga" key="manga" locks={@locks} target={@myself}>
              <.edit_select
                name="book[manga]"
                value={@draft["manga"]}
                prompt="Unknown"
                options={[{"No", "No"}, {"Yes", "Yes"}, {"Yes, right to left", "YesAndRightToLeft"}]}
                locked={"manga" in @locks}
              />
            </.edit_field>
            <.edit_field label="Black and white" key="black_and_white" locks={@locks} target={@myself}>
              <.edit_select
                name="book[black_and_white]"
                value={@draft["black_and_white"]}
                prompt="Unknown"
                options={[{"No", "false"}, {"Yes", "true"}]}
                locked={"black_and_white" in @locks}
              />
            </.edit_field>
            <.edit_field label="Scan information" key="scan_information" locks={@locks} target={@myself} class="col-span-2">
              <.edit_textarea
                name="book[scan_information]"
                rows="2"
                value={@draft["scan_information"]}
                locked={"scan_information" in @locks}
              />
            </.edit_field>
            <.edit_field label="Review" key="review" locks={@locks} target={@myself} class="col-span-2">
              <.edit_textarea name="book[review]" value={@draft["review"]} locked={"review" in @locks} />
            </.edit_field>
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

  attr :key, :string, required: true
  attr :label, :string, required: true
  attr :draft, :map, required: true
  attr :locks, :list, required: true
  attr :nonce, :integer, required: true
  attr :target, :any, required: true

  defp chip_field(assigns) do
    ~H"""
    <.edit_field label={@label} key={@key} locks={@locks} target={@target} class="col-span-2">
      <.edit_chips
        name={"book[#{@key}]"}
        key={@key}
        items={@draft[@key]}
        locked={@key in @locks}
        nonce={@nonce}
        target={@target}
      />
    </.edit_field>
    """
  end

  attr :name, :string, required: true
  attr :value, :string, default: "false"
  attr :locked, :boolean, default: false

  defp primary_flag(assigns) do
    ~H"""
    <label class="inline-flex items-center gap-1 text-xs text-fg-soft flex-shrink-0" title="Primary">
      <input type="hidden" name={@name} value={if @locked, do: @value, else: "false"} />
      <input
        :if={!@locked}
        type="checkbox"
        name={@name}
        value="true"
        checked={@value == "true"}
        class="ink-check"
      />
      <.icon :if={@locked and @value == "true"} name="lucide-star" class="w-3.5 h-3.5" /> Primary
    </label>
    """
  end
end
