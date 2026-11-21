# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.CollectionsLive do
  @moduledoc """
  `/collections`: the user's collections and the ones others share with
  them (`Stashix.Collections`), and a way to start a new one. Collections
  aren't narrowed by the Comics / Books switcher: they are the user's own
  mix.
  """
  use StashixWeb, :live_view

  import StashixWeb.CollectionComponents, only: [collection_card: 1]

  alias Phoenix.LiveView.JS
  alias Stashix.Collections
  alias Stashix.Library.Collection

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: gettext("Collections"), creating: nil) |> load()}
  end

  defp load(socket) do
    %{current_user: user, access: access} = socket.assigns
    {own, shared} = user |> Collections.list_for(access) |> Enum.split_with(& &1.own?)
    assign(socket, own: own, shared: shared)
  end

  @impl true
  def handle_event("new", _params, socket),
    do: {:noreply, assign(socket, creating: to_form(Collection.changeset(%Collection{}, %{}), as: :collection))}

  def handle_event("cancel_new", _params, socket), do: {:noreply, assign(socket, creating: nil)}

  def handle_event("validate_new", %{"collection" => params}, socket) do
    changeset = %Collection{} |> Collection.changeset(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, creating: to_form(changeset, as: :collection))}
  end

  def handle_event("create", %{"collection" => params}, socket) do
    case Collections.create(socket.assigns.current_user, params) do
      {:ok, collection} -> {:noreply, push_navigate(socket, to: ~p"/collection/#{collection.id}")}
      {:error, changeset} -> {:noreply, assign(socket, creating: to_form(changeset, as: :collection))}
    end
  end

  # Scan broadcasts reach every page through the sidebar subscriptions.
  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <.page wide>
      <.page_hero title={gettext("Collections")} eyebrow={gettext("Browse")} count={length(@own) + length(@shared)}>
        <:meta>
          <span>{gettext("Books and whole series, gathered your way.")}</span>
        </:meta>
        <:actions>
          <.ink_button id="new-collection" size="md" phx-click="new">
            <.icon name="lucide-plus" class="w-4 h-4" /> {gettext("New collection")}
          </.ink_button>
        </:actions>
      </.page_hero>

      <.section :if={@own != []} id="own-collections" title={gettext("Yours")} count={length(@own)} class="mt-10">
        <.collection_grid items={@own} />
      </.section>

      <div :if={@own == []} id="collections-empty" class="mt-10">
        <.empty_state icon="lucide-gallery-vertical-end" title={gettext("No collections yet")}>
          {gettext("Make one here, or use the Collection button on any book or series page to start one with it.")}
        </.empty_state>
      </div>

      <.section
        :if={@shared != []}
        id="shared-collections"
        title={gettext("Shared with you")}
        count={length(@shared)}
        class="mt-10"
      >
        <.collection_grid items={@shared} />
      </.section>

      <.dialog
        :if={@creating}
        id="new-collection-dialog"
        title={gettext("New collection")}
        on_close={JS.push("cancel_new")}
      >
        <.form for={@creating} id="new-collection-form" phx-change="validate_new" phx-submit="create" class="space-y-4">
          <.field label={gettext("Name")} error={field_error(@creating, :name)}>
            <.text_input name="collection[name]" value={@creating[:name].value} required maxlength="120" autofocus />
          </.field>
          <.field label={gettext("Description")} hint={gettext("Optional.")}>
            <.textarea name="collection[description]" value={@creating[:description].value} rows="3" maxlength="4000" />
          </.field>
          <.dialog_footer>
            <.ink_button type="button" variant="ghost" size="md" phx-click="cancel_new">{gettext("Cancel")}</.ink_button>
            <.ink_button type="submit" size="md">{gettext("Create")}</.ink_button>
          </.dialog_footer>
        </.form>
      </.dialog>
    </.page>
    """
  end

  attr :items, :list, required: true

  defp collection_grid(assigns) do
    ~H"""
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-4 gap-4">
      <div :for={item <- @items} id={"collection-#{item.collection.id}"}>
        <.collection_card
          navigate={~p"/collection/#{item.collection.id}"}
          name={item.collection.name}
          icon="lucide-gallery-vertical-end"
          covers={for id <- item.cover_ids, do: ~p"/api/books/#{id}/cover?s=sx"}
          stats={[{ngettext("book", "books", item.count), item.count}]}
          note={gettext("Empty — add books or series from their pages")}
        >
          <.pill :if={item.own? and item.collection.shared} tag="span" static>
            <.icon name="lucide-share-2" class="w-3 h-3" /> {gettext("Shared")}
          </.pill>
          <span :if={!item.own?} class="text-xs text-muted">
            {gettext("by %{name}", name: item.collection.user.username)}
          </span>
        </.collection_card>
      </div>
    </div>
    """
  end

  # Shown once the user has typed in the field or tried to submit.
  defp field_error(form, field) do
    case form[field].errors do
      [error | _] -> if form.source.action, do: translate_error(error)
      _ -> nil
    end
  end
end
