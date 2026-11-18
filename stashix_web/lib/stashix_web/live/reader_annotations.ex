# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.Live.ReaderAnnotations do
  @moduledoc """
  Highlights, notes and bookmarks in the readers (`StashixWeb.TextReaderLive`,
  `StashixWeb.ReaderLive`): the events both share and the Notes list.

  The reader's hook draws the annotations and reports new ones; this keeps
  the list (`:annotations`) and tells the hook what changed:

    * `"annotations:all"` — `%{items: [...]}`, once the book is open
    * `"annotations:put"` — `%{item: ...}`, added or recoloured
    * `"annotations:remove"` — `%{id: ...}`

  Each item is `%{id, kind, color, locator, note}`. The reader turns hook
  params into a locator itself (`locator_fun`), since only it knows its
  format.

  `:editing_note` is the annotation whose note is open for editing in the
  list.
  """
  use StashixWeb, :html

  import Phoenix.LiveView, only: [push_event: 3]

  alias Stashix.Annotations
  alias Stashix.Library.Annotation

  @colors Annotation.colors()

  @doc "The annotation assigns, for mount."
  def init(socket) do
    %{current_user: user, book: book} = socket.assigns
    assign(socket, annotations: Annotations.list(user.id, book.id), editing_note: nil)
  end

  @doc "Sends every annotation to the hook (once it has the book open)."
  def push_all(socket),
    do: push_event(socket, "annotations:all", %{items: Enum.map(socket.assigns.annotations, &item/1)})

  @doc "The shape the hooks draw from."
  def item(%Annotation{} = a), do: %{id: a.id, kind: a.kind, color: a.color, locator: a.locator, note: a.note}

  @doc """
  Handles an annotation event, or returns `:unhandled`. `locator_fun`
  builds the locator from the hook's params; `book_file` is what is read
  (image regions crop their preview from it).
  """
  def handle_event("annotate", params, socket, locator_fun, book_file) do
    %{access: access, current_user: user, book: book} = socket.assigns

    attrs = %{
      "kind" => params["kind"],
      "color" => if(params["kind"] == "highlight", do: params["color"] || "yellow"),
      "locator" => locator_fun.(params),
      "progression" => params["fraction"],
      "text" => params["text"],
      "note" => params["note"]
    }

    case Annotations.create(access, user.id, book, attrs, book_file) do
      {:ok, a} ->
        socket = assign(socket, annotations: sort(socket.assigns.annotations ++ [a]))
        socket = if params["edit"] == true, do: open_note(socket, a.id), else: socket
        {:reply, %{item: item(a)}, push_event(socket, "annotations:put", %{item: item(a)})}

      _ ->
        {:reply, %{error: true}, socket}
    end
  end

  def handle_event("annotation_color", %{"id" => id, "color" => color}, socket, _locator_fun, _book_file)
      when color in @colors do
    save(socket, id, %{"color" => color})
  end

  def handle_event("annotation_edit", %{"id" => id}, socket, _locator_fun, _book_file),
    do: {:noreply, open_note(socket, id)}

  def handle_event("annotation_note", %{"annotation" => id, "note" => note}, socket, _locator_fun, _book_file) do
    {:noreply, socket} = save(socket, id, %{"note" => note})
    {:noreply, assign(socket, :editing_note, nil)}
  end

  def handle_event("annotation_cancel", _params, socket, _locator_fun, _book_file),
    do: {:noreply, assign(socket, :editing_note, nil)}

  def handle_event("annotation_delete", %{"id" => id}, socket, _locator_fun, _book_file) do
    case Annotations.delete(socket.assigns.current_user.id, id) do
      {:ok, a} ->
        {:noreply,
         socket
         |> assign(annotations: Enum.reject(socket.assigns.annotations, &(&1.id == a.id)))
         |> push_event("annotations:remove", %{id: a.id})}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event(_event, _params, _socket, _locator_fun, _book_file), do: :unhandled

  defp save(socket, id, params) do
    case Annotations.update(socket.assigns.current_user.id, id, params) do
      {:ok, a} ->
        list = Enum.map(socket.assigns.annotations, &if(&1.id == a.id, do: a, else: &1))
        {:noreply, socket |> assign(:annotations, list) |> push_event("annotations:put", %{item: item(a)})}

      _ ->
        {:noreply, socket}
    end
  end

  # Opens the Notes panel on the annotation, its note ready to write.
  defp open_note(socket, id), do: assign(socket, editing_note: id, panel: "notes", overlay_visible: true)

  defp sort(list), do: Enum.sort_by(list, &{&1.progression, &1.inserted_at})

  @doc "Bookmarks among `annotations`."
  def bookmarks(annotations), do: Enum.filter(annotations, &(&1.kind == :bookmark))

  ## The Notes list

  attr :annotations, :list, required: true
  attr :editing_note, :string, default: nil
  attr :book, :map, required: true
  attr :outline, :list, default: nil

  @doc """
  The Notes tab: every highlight, note and bookmark in book order. Tapping
  one jumps to it (`"annotation_goto"`, the reader's own event); notes are
  written inline.
  """
  def notes_list(assigns) do
    ~H"""
    <div class="flex-1 min-h-0 flex flex-col">
      <%= if @annotations == [] do %>
        <p class="px-4 py-3 text-sm text-muted">
          {gettext(
            "No highlights, notes or bookmarks yet. Select text to highlight it, or bookmark a page from the top bar."
          )}
        </p>
      <% else %>
        <ol id="reader-notes" class="flex-1 overflow-y-auto overscroll-contain py-1">
          <li :for={a <- @annotations} id={"note-#{a.id}"} class="group relative border-b border-fg/5">
            <button
              phx-click="annotation_goto"
              phx-value-id={a.id}
              class="w-full flex gap-3 px-4 pt-2.5 pb-1 text-left hover:bg-fg/5 transition-colors"
            >
              <span class={["mt-1 w-1 self-stretch rounded-full flex-shrink-0", swatch_class(a)]} aria-hidden="true"></span>
              <span class="flex-1 min-w-0">
                <span class="flex items-center gap-1.5 text-[11px] uppercase tracking-[0.14em] text-muted">
                  <.icon name={kind_icon(a.kind)} class="w-3 h-3" />
                  {where_label(a)}
                </span>
                <img
                  :if={a.preview}
                  src={~p"/api/annotations/#{a.id}/preview"}
                  alt=""
                  loading="lazy"
                  class="mt-1.5 max-h-28 rounded-sm ring-1 ring-fg/10"
                />
                <span :if={a.text} class="mt-1 block text-sm text-fg-soft line-clamp-4">{a.text}</span>
                <span :if={a.note && @editing_note != a.id} class="mt-1 block text-sm text-fg whitespace-pre-line">{a.note}</span>
              </span>
            </button>

            <form
              :if={@editing_note == a.id}
              id={"note-form-#{a.id}"}
              phx-submit="annotation_note"
              class="px-4 pb-2.5 pl-8"
            >
              <input type="hidden" name="annotation" value={a.id} />
              <textarea
                name="note"
                rows="3"
                autofocus
                placeholder={gettext("Write a note")}
                class="w-full mt-1 px-2.5 py-2 rounded-md bg-fg/5 ring-1 ring-fg/15 text-sm text-fg placeholder:text-muted focus:outline-none focus:ring-ink"
              >{a.note}</textarea>
              <div class="mt-1.5 flex justify-end gap-2">
                <button
                  type="button"
                  phx-click="annotation_cancel"
                  class="px-2.5 h-7 rounded-md text-xs text-muted hover:text-fg"
                >
                  {gettext("Cancel")}
                </button>
                <button type="submit" class="px-2.5 h-7 rounded-md bg-ink text-zinc-950 text-xs font-semibold">
                  {gettext("Save")}
                </button>
              </div>
            </form>

            <div :if={@editing_note != a.id} class="flex items-center gap-1 px-4 pb-2 pl-8">
              <button
                :for={color <- Annotation.colors()}
                :if={a.kind != :bookmark}
                phx-click="annotation_color"
                phx-value-id={a.id}
                phx-value-color={color}
                title={color_label(color)}
                aria-label={color_label(color)}
                class={[
                  "w-4 h-4 rounded-full ring-offset-1 ring-offset-zinc-950",
                  color_bg(color),
                  a.color == color && "ring-2 ring-fg"
                ]}
              />
              <button
                :if={a.kind != :bookmark}
                phx-click="annotation_edit"
                phx-value-id={a.id}
                class="ml-2 inline-flex items-center gap-1 px-1.5 h-6 rounded text-xs text-muted hover:text-fg hover:bg-fg/10"
              >
                <.icon name="lucide-pencil" class="w-3 h-3" /> {if a.note, do: gettext("Edit note"), else: gettext("Note")}
              </button>
              <button
                phx-click="annotation_delete"
                phx-value-id={a.id}
                data-confirm={a.note && gettext("Delete this note?")}
                title={gettext("Delete")}
                aria-label={gettext("Delete")}
                class="ml-auto p-1 rounded text-muted hover:text-red-400 hover:bg-fg/10"
              >
                <.icon name="lucide-trash" class="w-3.5 h-3.5" />
              </button>
            </div>
          </li>
        </ol>
      <% end %>
      <div class="flex items-center gap-2 px-4 py-2 border-t border-fg/10 text-xs text-muted">
        <span>{ngettext("1 entry", "%{count} entries", length(@annotations))}</span>
        <span class="ml-auto">{gettext("Export")}</span>
        <a href={~p"/api/books/#{@book.id}/annotations/export?format=md"} class="text-fg-soft hover:text-fg underline">
          Markdown
        </a>
        <a href={~p"/api/books/#{@book.id}/annotations/export?format=json"} class="text-fg-soft hover:text-fg underline">
          JSON
        </a>
      </div>
    </div>
    """
  end

  @doc "Tailwind background of a highlight colour."
  def color_bg("green"), do: "bg-green-400"
  def color_bg("blue"), do: "bg-sky-400"
  def color_bg("pink"), do: "bg-pink-400"
  def color_bg(_yellow), do: "bg-yellow-300"

  defp swatch_class(%{kind: :highlight, color: color}), do: color_bg(color)
  defp swatch_class(%{kind: :bookmark}), do: "bg-ink"
  defp swatch_class(_note), do: "bg-fg/30"

  def color_label("green"), do: gettext("Green")
  def color_label("blue"), do: gettext("Blue")
  def color_label("pink"), do: gettext("Pink")
  def color_label(_yellow), do: gettext("Yellow")

  defp kind_icon(:bookmark), do: "lucide-bookmark"
  defp kind_icon(:note), do: "lucide-sticky-note"
  defp kind_icon(_highlight), do: "lucide-highlighter"

  @doc "Where an annotation is: its page, or how far through the book."
  def where_label(%{locator: %{"page" => page}}) when is_integer(page), do: gettext("Page %{page}", page: page + 1)
  def where_label(%{progression: p}), do: "#{round(p * 100)}%"
end
