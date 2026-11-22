# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.CardMenu do
  @moduledoc """
  The menu of a book or series card, opened with a long press or a right
  click (or the keyboard's context menu key) on any card that the bulk
  selection can pick (`data-select-id`, `data-select-type`, set by
  `media_card/1`). Lives once in the app layout (`id="card-menu"`).

  The `CardMenu` hook (`assets/js/hooks/card_menu.js`) spots the gesture and
  sends `"open"`; this component looks the item up for the viewer and shows
  what it is (series, year, pages, publisher, how far read) above its
  actions: read or continue, select (starts `StashixWeb.BulkSelect` with this
  card picked), add to collections, mark read or unread, download, open the
  series. Next to the pointer on wide screens, a sheet from the bottom on
  phones.
  """
  use StashixWeb, :live_component

  import Ecto.Query

  alias Phoenix.LiveView.JS
  alias Stashix.{Collections, Formatters, Library, Repo}
  alias Stashix.Library.{Access, Collection}

  @impl true
  def mount(socket), do: {:ok, assign(socket, info: nil, view: :main, creating: nil)}

  @impl true
  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  @impl true
  def handle_event("open", %{"type" => type, "id" => id}, socket) when type in ["book", "series"] do
    info =
      with {:ok, id} <- Ecto.UUID.cast(id),
           do: info(socket.assigns, String.to_existing_atom(type), id)

    {:noreply, assign(socket, info: if(is_map(info), do: info), view: :main, creating: nil)}
  end

  def handle_event("close", _params, socket), do: {:noreply, assign(socket, info: nil, creating: nil)}

  def handle_event("read", %{"read" => read}, socket) do
    %{current_user: user, access: access, info: info} = socket.assigns
    Library.set_read(access, user.id, [info.item], read == "true")
    {:noreply, assign(socket, info: nil)}
  end

  def handle_event("collections", _params, socket) do
    {:noreply, socket |> assign(view: :collections) |> load_collections()}
  end

  def handle_event("back", _params, socket), do: {:noreply, assign(socket, view: :main)}

  def handle_event("toggle", %{"id" => id}, socket) do
    %{current_user: user, access: access, info: info, containing: containing} = socket.assigns

    with %Collection{} = c <- Enum.find(socket.assigns.collections, &(&1.id == id)) do
      if containing[id] == :direct,
        do: Collections.remove(user, c, info.item),
        else: Collections.add(user, access, c, info.item)
    end

    {:noreply, load_collections(socket)}
  end

  def handle_event("new", _params, socket),
    do: {:noreply, assign(socket, creating: to_form(Collection.changeset(%Collection{}, %{}), as: :collection))}

  def handle_event("cancel_new", _params, socket), do: {:noreply, assign(socket, creating: nil)}

  def handle_event("create", %{"collection" => params}, socket) do
    %{current_user: user, access: access, info: info} = socket.assigns

    case Collections.create(user, params) do
      {:ok, c} ->
        Collections.add(user, access, c, info.item)
        {:noreply, socket |> assign(creating: nil) |> load_collections()}

      {:error, changeset} ->
        {:noreply, assign(socket, creating: to_form(changeset, as: :collection))}
    end
  end

  defp load_collections(socket) do
    %{current_user: user, info: info} = socket.assigns
    assign(socket, collections: Collections.own(user), containing: Collections.containing(user, info.item))
  end

  # What the header shows and the actions need, or nil when the viewer may
  # not see it.
  defp info(%{access: access, current_user: user}, :book, id) do
    with %{} = book <- Repo.one(from(b in Access.books(access), where: b.id == ^id and is_nil(b.deleted_at))) do
      book = Repo.preload(book, [:series, :publishers])
      progress = Library.get_progress(user.id, book.id)
      read = (progress && progress.progression) || 0.0
      number = book.series && Formatters.book_number_label(book)

      %{
        item: {:book, book.id},
        key: "book:#{book.id}",
        title: if(number, do: "#{book.series.name} #{number}", else: book.title),
        subtitle: if(number && book.title != book.series.name, do: book.title),
        cover: ~p"/api/books/#{book.id}/cover?s=s",
        facts: [
          book.series && !number && book.series.name,
          book.year && to_string(book.year),
          book.page_count > 0 && ngettext("1 page", "%{count} pages", book.page_count)
        ],
        more: [publisher(book.publishers), read_label(read)],
        read: read,
        started?: progress != nil and read > 0,
        all_read?: read >= 1.0,
        open: ~p"/read/#{book}",
        open_label: read_action(read),
        again: read >= 1.0 && ~p"/read/#{book}?page=0",
        series: book.series,
        download: Access.can_download?(access, book.library_id) && ~p"/api/books/#{book.id}/download"
      }
    end
  end

  defp info(%{access: access, current_user: user}, :series, id) do
    with %{} = series <- Repo.get(Access.series(access), id) do
      series = Repo.preload(series, :publishers)
      books = Library.picked_books(access, [{:series, series.id}])
      progress = Library.progress_map(user.id, Enum.map(books, & &1.id))
      done = Enum.count(books, &((progress[&1.id] || 0) >= 1))

      next =
        Enum.find(books, &((progress[&1.id] || 0) < 1 and progress[&1.id])) || Enum.find(books, &(!progress[&1.id]))

      novels? = Library.cached_library_kind(series.library_id) == :books

      %{
        item: {:series, series.id},
        key: "series:#{series.id}",
        title: series.name,
        subtitle: nil,
        cover: ~p"/api/series/#{series.id}/cover?s=s",
        facts: [Formatters.series_years(series), books != [] && series_count_label(length(books), novels?)],
        more: [
          publisher(series.publishers),
          books != [] && gettext("%{done} of %{total} read", done: done, total: length(books))
        ],
        started?: progress != %{},
        all_read?: books != [] and done == length(books),
        open: next && ~p"/read/#{next}",
        open_label: series_action(next, progress),
        again: books != [] && done == length(books) && ~p"/read/#{hd(books)}?page=0",
        series: nil,
        download: Access.can_download?(access, series.library_id) && ~p"/api/series/#{series.id}/download"
      }
    end
  end

  defp publisher([p | _]), do: p.name
  defp publisher(_), do: nil

  defp read_label(read) when read >= 1.0, do: gettext("Read")
  defp read_label(read) when read > 0, do: gettext("%{percent}% read", percent: round(read * 100))
  defp read_label(_), do: gettext("Unread")

  defp read_action(read) when read > 0 and read < 1.0, do: gettext("Continue")
  defp read_action(_), do: gettext("Read")

  defp series_action(nil, _progress), do: nil

  defp series_action(next, progress) do
    label = Formatters.book_number_label(next) || next.title

    if progress == %{},
      do: gettext("Start reading %{book}", book: label),
      else: gettext("Continue with %{book}", book: label)
  end

  defp line(parts), do: parts |> Enum.filter(&(is_binary(&1) and &1 != "")) |> Enum.join(" · ")

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} phx-hook="CardMenu" phx-target={@myself} data-open={@info && @info.key}>
      <div :if={@info} data-card-menu-backdrop class="fixed inset-0 z-50 bg-canvas/60 sm:bg-transparent"></div>
      <div
        :if={@info}
        id={"#{@id}-panel"}
        data-card-menu-panel
        role="menu"
        aria-label={@info.title}
        class="fixed z-50 inset-x-0 bottom-0 max-h-[85vh] overflow-y-auto overscroll-contain rounded-t-xl p-1.5 pb-[max(0.375rem,env(safe-area-inset-bottom))] bg-raised text-fg ring-1 ring-edge shadow-2xl sm:inset-x-auto sm:bottom-auto sm:w-80 sm:max-h-[min(32rem,calc(100vh-1rem))] sm:rounded-lg"
      >
        <div class="mx-auto mt-1 mb-2 h-1 w-10 rounded-full bg-fg/20 sm:hidden" aria-hidden="true"></div>
        <%= if @view == :main do %>
          <div class="flex gap-3 px-2 pt-1 pb-3">
            <img
              src={@info.cover}
              alt=""
              class="w-12 aspect-[2/3] flex-shrink-0 rounded-sm object-cover bg-surface ring-1 ring-edge"
            />
            <div class="min-w-0 text-sm">
              <p class="font-display font-bold text-fg leading-snug line-clamp-2">{@info.title}</p>
              <p :if={@info.subtitle} class="text-fg-soft truncate">{@info.subtitle}</p>
              <p :if={line(@info.facts) != ""} class="text-muted truncate">{line(@info.facts)}</p>
              <p :if={line(@info.more) != ""} class="text-muted truncate">{line(@info.more)}</p>
            </div>
          </div>
          <.menu_separator />
          <.menu_item :if={@info.open} icon="lucide-play" navigate={@info.open}>
            {@info.open_label}
          </.menu_item>
          <.menu_item :if={@info.again} icon="lucide-rotate-ccw" navigate={@info.again}>
            {gettext("Read again")}
          </.menu_item>
          <.menu_item
            icon="lucide-square-check"
            phx-click={
              JS.dispatch("bulk:start",
                to: "#bulk-select",
                detail: %{type: elem(@info.item, 0), id: elem(@info.item, 1)}
              )
            }
          >
            {gettext("Select")}
          </.menu_item>
          <.menu_item icon="lucide-gallery-vertical-end" keep_open phx-click="collections" phx-target={@myself}>
            <span class="flex items-center justify-between gap-3">
              {gettext("Add to collection")}
              <.icon name="lucide-chevron-right" class="w-3.5 h-3.5 text-muted" />
            </span>
          </.menu_item>
          <.menu_item
            :if={!@info.all_read?}
            icon="lucide-circle-check-big"
            phx-click="read"
            phx-value-read="true"
            phx-target={@myself}
          >
            {if elem(@info.item, 0) == :series, do: gettext("Mark all as read"), else: gettext("Mark as read")}
          </.menu_item>
          <.menu_item
            :if={@info.started?}
            icon="lucide-circle-x"
            phx-click="read"
            phx-value-read="false"
            phx-target={@myself}
          >
            {if elem(@info.item, 0) == :series, do: gettext("Mark all as unread"), else: gettext("Mark as unread")}
          </.menu_item>
          <.menu_item :if={@info.download} icon="lucide-download" href={@info.download}>
            {gettext("Download")}
          </.menu_item>
          <.menu_item :if={@info.series} icon="lucide-book-copy" navigate={~p"/series/#{slug_param(@info.series)}"}>
            {gettext("Open series")}
          </.menu_item>
        <% else %>
          <.menu_item icon="lucide-chevron-left" keep_open phx-click="back" phx-target={@myself}>
            {gettext("Back")}
          </.menu_item>
          <.menu_label>{gettext("Add “%{title}” to…", title: @info.title)}</.menu_label>
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
          <p :if={@collections == []} class="px-2 py-2 text-sm text-muted">
            {gettext("You have no collections yet.")}
          </p>
          <.menu_separator />
          <.menu_item icon="lucide-plus" keep_open phx-click="new" phx-target={@myself}>
            {gettext("New collection…")}
          </.menu_item>
        <% end %>
      </div>

      <.dialog
        :if={@info && @creating}
        id={"#{@id}-new"}
        title={gettext("New collection")}
        on_close={JS.push("cancel_new", target: @myself)}
      >
        <:description>{gettext("“%{title}” goes in it.", title: @info.title)}</:description>
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
