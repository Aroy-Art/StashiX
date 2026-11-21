# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.CollectionPicker do
  @moduledoc """
  The Collection button on book and series pages: a checklist of the
  user's own collections (`Stashix.Collections`) with a filter box. Ticking
  one adds the book or series, unticking removes it; the menu stays open.
  A book already in a collection through its series shows a half tick
  (ticking it adds the book on its own too). "New collection…" opens a
  dialog that makes one and adds the item to it.

      <.live_component module={StashixWeb.CollectionPicker} id="collection-picker"
        item={{:book, book.id}} title={book.title}
        current_user={@current_user} access={@access} />
  """
  use StashixWeb, :live_component

  alias Phoenix.LiveView.JS
  alias Stashix.Collections
  alias Stashix.Library.Collection

  @impl true
  def mount(socket), do: {:ok, assign(socket, creating: nil)}

  @impl true
  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> load()}
  end

  defp load(socket) do
    %{current_user: user, item: item} = socket.assigns
    assign(socket, collections: Collections.own(user), containing: Collections.containing(user, item))
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    %{current_user: user, access: access, item: item, containing: containing} = socket.assigns

    with %Collection{} = c <- Enum.find(socket.assigns.collections, &(&1.id == id)) do
      if containing[id] == :direct,
        do: Collections.remove(user, c, item),
        else: Collections.add(user, access, c, item)
    end

    notify(socket)
    {:noreply, load(socket)}
  end

  def handle_event("new", _params, socket),
    do: {:noreply, assign(socket, creating: to_form(Collection.changeset(%Collection{}, %{}), as: :collection))}

  def handle_event("cancel_new", _params, socket), do: {:noreply, assign(socket, creating: nil)}

  def handle_event("create", %{"collection" => params}, socket) do
    %{current_user: user, access: access, item: item} = socket.assigns

    case Collections.create(user, params) do
      {:ok, c} ->
        Collections.add(user, access, c, item)
        notify(socket)
        {:noreply, socket |> assign(creating: nil) |> load()}

      {:error, changeset} ->
        {:noreply, assign(socket, creating: to_form(changeset, as: :collection))}
    end
  end

  # The page may show which collections hold the item.
  defp notify(socket), do: send(self(), {:collections_changed, socket.assigns.item})

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="self-stretch flex">
      <.ink_menu id={"#{@id}-menu"} align="start" class="self-stretch" panel_class="w-72 max-w-[calc(100vw-2rem)]">
        <:trigger class={[text_link_class("ink"), "h-full"]} label={gettext("Add to a collection")}>
          <.icon name="lucide-gallery-vertical-end" class="w-4 h-4" />
          <span class="hidden sm:inline">{gettext("Collection")}</span>
          <.icon name="lucide-chevron-down" class="w-3.5 h-3.5 -ml-1" />
        </:trigger>
        <.menu_label>{gettext("Add “%{title}” to…", title: @title)}</.menu_label>
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
          id={"#{@id}-#{c.id}"}
          keep_open
          icon={tick_icon(@containing[c.id])}
          icon_class={@containing[c.id] && "text-ink"}
          phx-click="toggle"
          phx-value-id={c.id}
          phx-target={@myself}
          data-label={c.name}
          aria-checked={to_string(@containing[c.id] == :direct)}
        >
          <span class="flex items-baseline justify-between gap-3">
            <span class="truncate">{c.name}</span>
            <span
              :if={@containing[c.id] == :series}
              class="font-sans font-normal normal-case tracking-normal text-xs text-muted"
            >
              {gettext("via series")}
            </span>
          </span>
        </.menu_item>
        <p :if={@collections != []} data-menu-empty hidden class="px-2 py-2 text-sm text-muted">
          {gettext("No matches")}
        </p>
        <p :if={@collections == []} class="px-2 py-2 text-sm text-muted">{gettext("You have no collections yet.")}</p>
        <.menu_separator />
        <.menu_item icon="lucide-plus" phx-click="new" phx-target={@myself}>{gettext("New collection…")}</.menu_item>
      </.ink_menu>

      <.dialog
        :if={@creating}
        id={"#{@id}-new"}
        title={gettext("New collection")}
        on_close={JS.push("cancel_new", target: @myself)}
      >
        <:description>{gettext("“%{title}” goes in it.", title: @title)}</:description>
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

  defp tick_icon(:direct), do: "lucide-square-check"
  defp tick_icon(:series), do: "lucide-square-dot"
  defp tick_icon(_), do: "lucide-square"

  defp name_error(form) do
    case form[:name].errors do
      [error | _] -> if form.source.action, do: translate_error(error)
      _ -> nil
    end
  end
end
