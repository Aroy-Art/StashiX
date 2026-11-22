# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.BulkSelect do
  @moduledoc """
  Picking several books and series on a grid to add them to a collection at
  once. Lives once in the app layout (`id="bulk-select"`).

  The Select button of a toolbar (`StashixWeb.CoreComponents.select_button/1`)
  turns the mode on; the `BulkSelect` hook (`assets/js/hooks/bulk_select.js`)
  then turns clicks on cards (`data-select-id`, `data-select-type`, set by
  `media_card/1`) into ticks, shift-click picks a range, Esc leaves. The hook
  reports the mode (`"mode"`) and the picked items (`"selection"`); this
  component shows the bar at the bottom and adds them to the collection
  chosen there, or to a new one. Its ⋯ menu marks them read or unread and
  downloads them as one ZIP (the hook posts them to `/api/download`).

  The card menu (`StashixWeb.CardMenu`) also starts the mode, with the card
  it was opened on picked.
  """
  use StashixWeb, :live_component

  alias Phoenix.LiveView.JS
  alias Stashix.Collections
  alias Stashix.Library.Collection

  @impl true
  def mount(socket),
    do: {:ok, assign(socket, active: false, items: [], collections: [], notice: nil, creating: nil)}

  @impl true
  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  @impl true
  def handle_event("mode", %{"on" => on}, socket) do
    collections = if on, do: Collections.own(socket.assigns.current_user), else: []
    {:noreply, assign(socket, active: on, items: [], notice: nil, collections: collections)}
  end

  def handle_event("selection", %{"items" => items}, socket) when is_list(items) do
    items =
      for %{"type" => type, "id" => id} <- items,
          type in ["book", "series"],
          {:ok, id} <- [Ecto.UUID.cast(id)],
          do: {String.to_existing_atom(type), id}

    {:noreply, assign(socket, items: items, notice: nil)}
  end

  def handle_event("add", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.collections, &(&1.id == id)) do
      nil -> {:noreply, socket}
      c -> {:noreply, add_all(socket, c)}
    end
  end

  def handle_event("read", %{"read" => read}, socket) do
    %{current_user: user, access: access, items: items} = socket.assigns
    ids = Stashix.Library.set_read(access, user.id, items, read == "true")
    count = length(ids)
    # The page redraws the cards' read marks (StashixWeb.Live.Hooks).
    send(self(), {:read_changed, Map.new(ids, &{&1, if(read == "true", do: 1.0, else: 0.0)})})

    text =
      if read == "true",
        do: ngettext("Marked 1 book as read.", "Marked %{count} books as read.", count),
        else: ngettext("Marked 1 book as unread.", "Marked %{count} books as unread.", count)

    {:noreply, assign(socket, notice: %{text: text, id: nil})}
  end

  def handle_event("new", _params, socket),
    do: {:noreply, assign(socket, creating: to_form(Collection.changeset(%Collection{}, %{}), as: :collection))}

  def handle_event("cancel_new", _params, socket), do: {:noreply, assign(socket, creating: nil)}

  def handle_event("create", %{"collection" => params}, socket) do
    case Collections.create(socket.assigns.current_user, params) do
      {:ok, c} ->
        socket = assign(socket, creating: nil, collections: Collections.own(socket.assigns.current_user))
        {:noreply, add_all(socket, c)}

      {:error, changeset} ->
        {:noreply, assign(socket, creating: to_form(changeset, as: :collection))}
    end
  end

  # Adds every picked item; the picks are cleared, the mode stays on.
  defp add_all(socket, c) do
    %{current_user: user, access: access, items: items} = socket.assigns
    added = Enum.count(items, &match?({:ok, %{}}, Collections.add(user, access, c, &1)))
    there = length(items) - added

    notice =
      cond do
        there == 0 ->
          ngettext("Added 1 to %{name}.", "Added %{count} to %{name}.", added, name: c.name)

        added == 0 ->
          gettext("All of them were already in %{name}.", name: c.name)

        true ->
          ngettext("Added 1 to %{name}", "Added %{count} to %{name}", added, name: c.name) <>
            "; " <>
            ngettext("1 was already there.", "%{count} were already there.", there)
      end

    socket
    |> assign(items: [], notice: %{text: notice, id: c.id})
    |> push_event("bulk:clear", %{})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} phx-hook="BulkSelect" phx-target={@myself} data-active={to_string(@active)}>
      <div
        :if={@active}
        id={"#{@id}-bar"}
        role="toolbar"
        aria-label={gettext("Selection")}
        class="fixed bottom-4 left-1/2 -translate-x-1/2 z-40 w-[calc(100%-2rem)] max-w-2xl flex flex-wrap items-center gap-x-4 gap-y-2 px-4 py-3 rounded-lg bg-raised text-fg ring-1 ring-edge shadow-2xl"
      >
        <p class="text-sm tabular-nums">
          <%= cond do %>
            <% @notice && @notice.id -> %>
              <.link navigate={~p"/collection/#{@notice.id}"} class="text-ink hover:underline">{@notice.text}</.link>
            <% @notice -> %>
              <span class="text-ink">{@notice.text}</span>
            <% @items == [] -> %>
              <span class="text-muted">{gettext("Tap books or series to pick them; Shift picks a range.")}</span>
            <% true -> %>
              <span class="font-semibold">{ngettext("1 selected", "%{count} selected", length(@items))}</span>
          <% end %>
        </p>
        <div class="ml-auto flex items-center gap-3">
          <.ink_menu id={"#{@id}-menu"} align="end" panel_class="w-72 max-w-[calc(100vw-2rem)]">
            <:trigger
              class={[
                "inline-flex items-center gap-2 h-9 px-4 rounded-full text-sm font-semibold transition-colors",
                if(@items == [], do: "bg-fg/10 text-muted pointer-events-none", else: "bg-ink text-zinc-950")
              ]}
              label={gettext("Add to collection")}
            >
              <.icon name="lucide-plus" class="w-4 h-4" /> {gettext("Add to collection")}
              <.icon name="lucide-chevron-up" class="w-3.5 h-3.5" />
            </:trigger>
            <div :if={@collections != []} class="sticky -top-1.5 z-10 -mx-1.5 mb-1 px-1.5 pb-1.5 bg-raised">
              <input
                type="text"
                form=""
                data-menu-filter
                placeholder={gettext("Find a collection")}
                aria-label={gettext("Find a collection")}
                autocomplete="off"
                class="w-full bg-surface border border-line rounded-sm px-2.5 py-1.5 text-sm text-fg placeholder-faint focus:outline-none focus:border-ink"
              />
            </div>
            <.menu_item
              :for={c <- @collections}
              icon="lucide-gallery-vertical-end"
              phx-click="add"
              phx-value-id={c.id}
              phx-target={@myself}
              data-label={c.name}
            >
              <span class="truncate">{c.name}</span>
            </.menu_item>
            <p :if={@collections != []} data-menu-empty hidden class="px-2 py-2 text-sm text-muted">
              {gettext("No matches")}
            </p>
            <.menu_separator :if={@collections != []} />
            <.menu_item icon="lucide-plus" phx-click="new" phx-target={@myself}>{gettext("New collection…")}</.menu_item>
          </.ink_menu>
          <.ink_menu id={"#{@id}-more"} align="end" panel_class="w-56">
            <:trigger
              class={[
                "inline-flex items-center justify-center w-9 h-9 rounded-full transition-colors",
                if(@items == [], do: "text-faint pointer-events-none", else: "text-fg-soft hover:text-fg hover:bg-fg/10")
              ]}
              label={gettext("More actions")}
            >
              <.icon name="lucide-ellipsis" class="w-4 h-4" />
            </:trigger>
            <.menu_item icon="lucide-circle-check-big" phx-click="read" phx-value-read="true" phx-target={@myself}>
              {gettext("Mark as read")}
            </.menu_item>
            <.menu_item icon="lucide-circle-x" phx-click="read" phx-value-read="false" phx-target={@myself}>
              {gettext("Mark as unread")}
            </.menu_item>
            <.menu_separator />
            <.menu_item icon="lucide-download" phx-click={JS.dispatch("bulk:download", to: "##{@id}")}>
              {gettext("Download as ZIP")}
            </.menu_item>
          </.ink_menu>
          <.text_link type="button" tone="subtle" phx-click={JS.dispatch("bulk:clear", to: "##{@id}")}>
            {gettext("Clear")}
          </.text_link>
          <.text_link type="button" tone="subtle" phx-click={JS.dispatch("bulk:toggle", to: "##{@id}")}>
            {gettext("Done")}
          </.text_link>
        </div>
      </div>

      <.dialog
        :if={@creating}
        id={"#{@id}-new"}
        title={gettext("New collection")}
        on_close={JS.push("cancel_new", target: @myself)}
      >
        <:description>
          {ngettext("The book or series you picked goes in it.", "The %{count} you picked go in it.", length(@items))}
        </:description>
        <.form for={@creating} id={"#{@id}-new-form"} phx-submit="create" phx-target={@myself} class="space-y-4">
          <.field label={gettext("Name")} error={name_error(@creating)}>
            <.text_input name="collection[name]" value={@creating[:name].value} required maxlength="120" autofocus />
          </.field>
          <.dialog_footer>
            <.ink_button type="button" variant="ghost" size="md" phx-click="cancel_new" phx-target={@myself}>
              {gettext("Cancel")}
            </.ink_button>
            <.ink_button type="submit" size="md">{gettext("Create and add")}</.ink_button>
          </.dialog_footer>
        </.form>
      </.dialog>
    </div>
    """
  end

  defp name_error(form) do
    case form[:name].errors do
      [error | _] -> if form.source.action, do: translate_error(error)
      _ -> nil
    end
  end
end
