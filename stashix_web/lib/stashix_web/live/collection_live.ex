# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.CollectionLive do
  @moduledoc """
  `/collection/:id`: one collection (`Stashix.Collections`).

  In its own order it shows its entries, books and whole series, as cards;
  sorted by title, year or date added it shows every book, series opened up.
  "Read next" is the first unfinished book in collection order. The owner
  edits the name and description, shares it, removes and moves entries;
  others see it read-only, limited to what they may read.
  """
  use StashixWeb, :live_view

  alias Phoenix.LiveView.JS
  alias Stashix.{Collections, Library}
  alias Stashix.Library.Collection

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @page_size 48

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    %{current_user: user, access: access} = socket.assigns

    case Collections.get(user, access, id) do
      {:ok, collection} ->
        {:ok,
         assign(socket,
           collection: collection,
           owner?: Collections.owner?(collection, user),
           page_title: collection.name,
           editing: nil
         )}

      {:error, :not_found} ->
        {:ok,
         socket |> put_flash(:error, gettext("That collection isn't there.")) |> push_navigate(to: ~p"/collections")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    sort = if params["sort"] in Collection.sorts(), do: params["sort"], else: socket.assigns.collection.default_sort

    page =
      case Integer.parse(params["page"] || "1"),
        do: (
          {n, ""} when n > 0 -> n
          _ -> 1
        )

    {:noreply, socket |> assign(sort: sort, page: page) |> load()}
  end

  defp load(socket) do
    %{access: access, collection: c, current_user: user, sort: sort, page: page} = socket.assigns
    {all_books, total} = Collections.books(access, c)
    progress = Library.progress_map(user.id, Enum.map(all_books, & &1.id))
    read = if total > 0, do: Enum.sum(Map.values(progress)) / total, else: 0.0

    {entries, books, total_pages} =
      if sort == "position" do
        {Collections.entries(access, c), [], 1}
      else
        {books, _} = Collections.books(access, c, sort, limit: @page_size, offset: (page - 1) * @page_size)
        {[], books, max(1, ceil(total / @page_size))}
      end

    assign(socket,
      entries: entries,
      books: books,
      total: total,
      total_pages: total_pages,
      series_count: Enum.count(entries, & &1.series_id),
      progress: progress,
      read: read,
      read_next: Enum.find(all_books, &((progress[&1.id] || 0.0) < 1.0)),
      cover: List.first(all_books)
    )
  end

  defp collection_path(socket, params) do
    params = Map.merge(%{sort: socket.assigns.sort}, params)
    params = if params.sort == socket.assigns.collection.default_sort, do: Map.delete(params, :sort), else: params
    ~p"/collection/#{socket.assigns.collection.id}?#{params}"
  end

  ## Events

  @impl true
  def handle_event("sort", %{"value" => sort}, socket),
    do: {:noreply, push_patch(socket, to: collection_path(socket, %{sort: sort}))}

  def handle_event("goto_page", %{"page" => p}, socket) do
    page = p |> String.to_integer() |> max(1) |> min(socket.assigns.total_pages)
    {:noreply, push_patch(socket, to: collection_path(socket, %{page: page}))}
  end

  def handle_event("edit", _params, socket),
    do:
      {:noreply,
       assign(socket, editing: to_form(Collection.changeset(socket.assigns.collection, %{}), as: :collection))}

  def handle_event("cancel_edit", _params, socket), do: {:noreply, assign(socket, editing: nil)}

  def handle_event("validate_edit", %{"collection" => params}, socket) do
    changeset = socket.assigns.collection |> Collection.changeset(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, editing: to_form(changeset, as: :collection))}
  end

  def handle_event("save_edit", %{"collection" => params}, socket) do
    case Collections.update(socket.assigns.current_user, socket.assigns.collection, params) do
      {:ok, c} ->
        {:noreply, socket |> assign(editing: nil) |> reloaded(c) |> push_patch(to: ~p"/collection/#{c.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, editing: to_form(changeset, as: :collection))}

      {:error, :forbidden} ->
        {:noreply, assign(socket, editing: nil)}
    end
  end

  def handle_event("toggle_share", _params, socket) do
    c = socket.assigns.collection

    case Collections.update(socket.assigns.current_user, c, %{shared: !c.shared}) do
      {:ok, c} ->
        message =
          if c.shared,
            do: gettext("Shared: everyone sees the books in it they may read."),
            else: gettext("No longer shared.")

        {:noreply, socket |> reloaded(c) |> put_flash(:info, message)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete", _params, socket) do
    case Collections.delete(socket.assigns.current_user, socket.assigns.collection) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, gettext("Collection deleted.")) |> push_navigate(to: ~p"/collections")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_entry", %{"id" => id}, socket) do
    Collections.remove_entry(socket.assigns.current_user, socket.assigns.collection, id)
    {:noreply, load(socket)}
  end

  def handle_event("move_entry", %{"id" => id, "to" => to}, socket) do
    index = if to == "top", do: 0, else: length(socket.assigns.entries)
    Collections.move(socket.assigns.current_user, socket.assigns.collection, id, index)
    {:noreply, load(socket)}
  end

  # Drag and drop (the Sortable hook): the entry's new place among the rest.
  def handle_event("reorder", %{"id" => id, "index" => index}, socket) when is_integer(index) do
    Collections.move(socket.assigns.current_user, socket.assigns.collection, id, index)
    {:noreply, load(socket)}
  end

  defp reloaded(socket, c) do
    c = Stashix.Repo.preload(c, :user)
    socket |> assign(collection: c, page_title: c.name) |> load()
  end

  # Scan broadcasts reach every page through the sidebar subscriptions.
  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  ## Render

  @impl true
  def render(assigns) do
    ~H"""
    <.page wide fade cover_src={@cover && ~p"/api/books/#{@cover.id}/cover?s=s"}>
      <.page_hero title={@collection.name} eyebrow={eyebrow(@collection, @owner?)} count={@total > 0 && @total}>
        <:meta>
          <span>
            <span class="text-fg font-semibold">{@total}</span> {ngettext("book", "books", @total)}
          </span>
          <span :if={@series_count > 0}>{ngettext("1 series", "%{count} series", @series_count)}</span>
          <span :if={@read > 0}>{gettext("%{percent}% read", percent: round(@read * 100))}</span>
        </:meta>
        <:actions>
          <.ink_button :if={@read_next} id="read-next" size="md" navigate={~p"/read/#{slug_param(@read_next)}"}>
            <.icon name="lucide-play" class="w-4 h-4" />
            {gettext("Read next: %{title}", title: StashixWeb.Opds.entry_title(@read_next))}
          </.ink_button>
          <.sort_select id="collection-sort" options={sort_options()} selected={@sort} />
          <.ink_menu :if={@owner?} id="collection-menu">
            <:trigger
              class="flex items-center justify-center w-9 h-9 rounded-full bg-fg/5 hover:bg-fg/15 text-fg-soft hover:text-fg transition-colors"
              label={gettext("Collection actions")}
            >
              <.icon name="lucide-ellipsis" class="w-4 h-4" />
            </:trigger>
            <.menu_item icon="lucide-pencil" phx-click="edit">{gettext("Edit name and description")}</.menu_item>
            <.menu_item icon="lucide-share-2" phx-click="toggle_share">
              {if @collection.shared, do: gettext("Stop sharing"), else: gettext("Share with everyone")}
            </.menu_item>
            <.menu_separator />
            <.menu_item
              icon="lucide-trash"
              tone="danger"
              phx-click="delete"
              data-confirm={gettext("Delete the collection “%{name}”? The books stay.", name: @collection.name)}
            >
              {gettext("Delete collection")}
            </.menu_item>
          </.ink_menu>
        </:actions>
      </.page_hero>

      <p :if={@collection.description} id="collection-description" class="mt-4 max-w-3xl text-fg-soft whitespace-pre-line">
        {@collection.description}
      </p>

      <div class="mt-8">
        <%= if @sort == "position" do %>
          <.cover_grid :if={@entries != []} id="collection-entries">
            <div :for={entry <- @entries} id={"entry-#{entry.id}"} data-entry-id={entry.id} class="relative group/entry">
              <.book_card
                :if={entry.book}
                book={entry.book}
                as={if entry.book.series, do: :issue, else: :book}
                read={@progress[entry.book.id]}
              />
              <.series_card :if={entry.series} series={entry.series} subtitle={gettext("Whole series")} />
              <.entry_menu :if={@owner?} entry={entry} />
            </div>
          </.cover_grid>
        <% else %>
          <.pagination id="page-top" page={@page} total_pages={@total_pages} />
          <.cover_grid id="collection-books">
            <.book_card
              :for={book <- @books}
              book={book}
              as={if book.series, do: :issue, else: :book}
              read={@progress[book.id]}
            />
          </.cover_grid>
          <.pagination page={@page} total_pages={@total_pages} scroll_to="page-top" />
        <% end %>

        <div :if={@total == 0} id="collection-empty">
          <.empty_state icon="lucide-gallery-vertical-end" title={gettext("Nothing in this collection yet")}>
            {if @owner?,
              do: gettext("Use the Collection button on a book or series page to add it here."),
              else: gettext("Nothing here you can read.")}
          </.empty_state>
        </div>
      </div>

      <.dialog
        :if={@editing}
        id="edit-collection-dialog"
        title={gettext("Edit collection")}
        on_close={JS.push("cancel_edit")}
      >
        <.form for={@editing} id="edit-collection-form" phx-change="validate_edit" phx-submit="save_edit" class="space-y-4">
          <.field label={gettext("Name")} error={field_error(@editing, :name)}>
            <.text_input name="collection[name]" value={@editing[:name].value} required maxlength="120" />
          </.field>
          <.field label={gettext("Description")} hint={gettext("Optional.")}>
            <.textarea name="collection[description]" value={@editing[:description].value} rows="4" maxlength="4000" />
          </.field>
          <.field label={gettext("Opens sorted by")}>
            <.ink_select
              id="edit-collection-sort"
              name="collection[default_sort]"
              value={@editing[:default_sort].value}
              options={sort_options()}
            />
          </.field>
          <.dialog_footer>
            <.ink_button type="button" variant="ghost" size="md" phx-click="cancel_edit">{gettext("Cancel")}</.ink_button>
            <.ink_button type="submit" size="md">{gettext("Save")}</.ink_button>
          </.dialog_footer>
        </.form>
      </.dialog>
    </.page>
    """
  end

  attr :entry, :map, required: true

  # The owner's menu on a card: sits over the card's corner, outside its link.
  defp entry_menu(assigns) do
    ~H"""
    <div class="absolute top-1.5 right-1.5 z-10">
      <.ink_menu id={"entry-menu-#{@entry.id}"}>
        <:trigger
          class="p-1.5 rounded-md bg-canvas/80 text-fg-soft hover:text-fg ring-1 ring-edge opacity-100 sm:opacity-0 sm:group-hover/entry:opacity-100 focus:opacity-100 transition-opacity"
          label={gettext("Entry actions")}
        >
          <.icon name="lucide-ellipsis-vertical" class="w-4 h-4" />
        </:trigger>
        <.menu_item icon="lucide-arrow-up-to-line" phx-click="move_entry" phx-value-id={@entry.id} phx-value-to="top">
          {gettext("Move to top")}
        </.menu_item>
        <.menu_item icon="lucide-arrow-down-to-line" phx-click="move_entry" phx-value-id={@entry.id} phx-value-to="bottom">
          {gettext("Move to bottom")}
        </.menu_item>
        <.menu_separator />
        <.menu_item icon="lucide-x" tone="danger" phx-click="remove_entry" phx-value-id={@entry.id}>
          {gettext("Remove from collection")}
        </.menu_item>
      </.ink_menu>
    </div>
    """
  end

  defp eyebrow(c, true),
    do: if(c.shared, do: gettext("Collection · yours · shared"), else: gettext("Collection · yours"))

  defp eyebrow(c, false), do: gettext("Collection · shared by %{name}", name: c.user.username)

  defp sort_options do
    [
      {gettext("Collection order"), "position"},
      {gettext("Title"), "title"},
      {gettext("Year"), "year"},
      {gettext("Date added"), "added"}
    ]
  end

  # Shown once the form has been changed or submitted.
  defp field_error(form, field) do
    case form[field].errors do
      [error | _] -> if form.source.action, do: translate_error(error)
      _ -> nil
    end
  end
end
