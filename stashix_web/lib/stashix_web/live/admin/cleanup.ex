# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.AdminLive.Cleanup do
  @moduledoc """
  Cleanup tab: restore or purge soft-deleted series and books.

  Markup only: `StashixWeb.AdminLive` owns the state and handles every event.
  """
  use StashixWeb, :html

  attr :deleted_books, :any, required: true
  attr :deleted_series, :any, required: true
  attr :selected_books, :any, required: true
  attr :selected_series, :any, required: true

  def tab(assigns) do
    ~H"""
    <% all_series_ids = Enum.map(@deleted_series, & &1.id) |> MapSet.new()
    all_books_ids = Enum.map(@deleted_books, & &1.id) |> MapSet.new()
    all_series_selected = @deleted_series != [] and @selected_series == all_series_ids
    all_books_selected = @deleted_books != [] and @selected_books == all_books_ids
    series_sel_count = MapSet.size(@selected_series)
    books_sel_count = MapSet.size(@selected_books) %>
    <div class="space-y-8">
      <.display_heading level={1} class="text-4xl!">{gettext("Cleanup")}</.display_heading>
      <%!-- Series section --%>
      <div class="space-y-3">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 class="font-display font-black uppercase text-2xl leading-none text-fg">
            {gettext("Deleted Series")} <span class="ml-2 text-sm font-normal text-muted">({length(@deleted_series)})</span>
          </h2>
          <%= if series_sel_count > 0 do %>
            <div class="flex flex-wrap items-center gap-2 sm:gap-3 w-full sm:w-auto">
              <span class="text-sm text-muted">{gettext("%{count} selected", count: series_sel_count)}</span>
              <.ink_button
                size="md"
                phx-click="batch_restore_series"
              >
                {gettext("Restore Selected")}
              </.ink_button>
              <.ink_button
                variant="danger"
                size="md"
                phx-click="show_confirm"
                phx-value-event="batch_purge_series"
                phx-value-title={gettext("Purge Series")}
                phx-value-message={
                  ngettext(
                    "Permanently delete 1 series and ALL its books? Book files on disk are never deleted. This cannot be undone.",
                    "Permanently delete %{count} series and ALL their books? Book files on disk are never deleted. This cannot be undone.",
                    series_sel_count
                  )
                }
                phx-value-label={gettext("Purge")}
              >
                {gettext("Purge Selected")}
              </.ink_button>
            </div>
          <% end %>
        </div>
        <%= if @deleted_series == [] do %>
          <p class="text-muted text-sm">{gettext("No deleted series.")}</p>
        <% else %>
          <%!-- Mobile card list — hidden on sm+ --%>
          <div class="sm:hidden bg-surface rounded-lg ring-1 ring-edge divide-y divide-fg/10 overflow-hidden">
            <label class="flex items-center gap-3 px-4 py-2.5 text-[10px] font-bold tracking-[0.18em] uppercase text-muted">
              <input
                type="checkbox"
                phx-click="select_all_series"
                checked={all_series_selected}
                class="ink-check"
              />
              {gettext("Select all")}
            </label>
            <%= for s <- @deleted_series do %>
              <div class={[
                "flex items-start gap-3 px-4 py-3 transition-colors",
                if(MapSet.member?(@selected_series, s.id), do: "bg-accent/10", else: "")
              ]}>
                <input
                  type="checkbox"
                  phx-click="toggle_series"
                  phx-value-id={s.id}
                  checked={MapSet.member?(@selected_series, s.id)}
                  class="ink-check mt-0.5"
                />
                <div class="min-w-0 flex-1">
                  <p class="text-fg font-medium break-words">{s.name}</p>
                  <p class="text-xs text-muted mt-0.5">
                    {s.library.name} ·
                    <.local_time id={"deleted-series-m-#{s.id}"} value={s.deleted_at} format="datetime" />
                  </p>
                  <div class="flex gap-2 mt-2">
                    <.series_actions series={s} />
                  </div>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Desktop table — hidden below sm --%>
          <div class="hidden sm:block bg-surface rounded-lg ring-1 ring-edge overflow-hidden">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-fg/10">
                  <th class="px-4 py-3 w-8">
                    <input
                      type="checkbox"
                      phx-click="select_all_series"
                      checked={all_series_selected}
                      class="ink-check"
                    />
                  </th>
                  <th class="px-4 py-3 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-muted">
                    {gettext("Series")}
                  </th>
                  <th class="px-4 py-3 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-muted">
                    {gettext("Library")}
                  </th>
                  <th class="hidden md:table-cell px-4 py-3 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-muted">
                    {gettext("Deleted")}
                  </th>
                  <th class="px-4 py-3"></th>
                </tr>
              </thead>
              <tbody>
                <%= for s <- @deleted_series do %>
                  <tr class={[
                    "border-b border-fg/10 last:border-0 transition-colors",
                    if(MapSet.member?(@selected_series, s.id), do: "bg-accent/10", else: "")
                  ]}>
                    <td class="px-4 py-3">
                      <input
                        type="checkbox"
                        phx-click="toggle_series"
                        phx-value-id={s.id}
                        checked={MapSet.member?(@selected_series, s.id)}
                        class="ink-check"
                      />
                    </td>
                    <td class="px-4 py-3 text-fg">{s.name}</td>
                    <td class="px-4 py-3 text-muted">{s.library.name}</td>
                    <td class="hidden md:table-cell px-4 py-3 text-muted text-xs whitespace-nowrap">
                      <.local_time id={"deleted-series-#{s.id}"} value={s.deleted_at} format="datetime" />
                    </td>
                    <td class="px-4 py-3">
                      <div class="flex gap-3 justify-end">
                        <.series_actions series={s} />
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>

      <%!-- Books section --%>
      <div class="space-y-3">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 class="font-display font-black uppercase text-2xl leading-none text-fg">
            {gettext("Deleted Books")} <span class="ml-2 text-sm font-normal text-muted">({length(@deleted_books)})</span>
          </h2>
          <%= if books_sel_count > 0 do %>
            <div class="flex flex-wrap items-center gap-2 sm:gap-3 w-full sm:w-auto">
              <span class="text-sm text-muted">{gettext("%{count} selected", count: books_sel_count)}</span>
              <.ink_button
                size="md"
                phx-click="batch_restore_books"
              >
                {gettext("Restore Selected")}
              </.ink_button>
              <.ink_button
                variant="danger"
                size="md"
                phx-click="show_confirm"
                phx-value-event="batch_purge_books"
                phx-value-title={gettext("Purge Books")}
                phx-value-message={
                  ngettext(
                    "Permanently delete 1 book? Book files on disk are never deleted. This cannot be undone.",
                    "Permanently delete %{count} books? Book files on disk are never deleted. This cannot be undone.",
                    books_sel_count
                  )
                }
                phx-value-label={gettext("Purge")}
              >
                {gettext("Purge Selected")}
              </.ink_button>
            </div>
          <% end %>
        </div>
        <%= if @deleted_books == [] do %>
          <p class="text-muted text-sm">{gettext("No deleted books.")}</p>
        <% else %>
          <%!-- Mobile card list — hidden on sm+ --%>
          <div class="sm:hidden bg-surface rounded-lg ring-1 ring-edge divide-y divide-fg/10 overflow-hidden">
            <label class="flex items-center gap-3 px-4 py-2.5 text-[10px] font-bold tracking-[0.18em] uppercase text-muted">
              <input
                type="checkbox"
                phx-click="select_all_books"
                checked={all_books_selected}
                class="ink-check"
              />
              {gettext("Select all")}
            </label>
            <%= for b <- @deleted_books do %>
              <div class={[
                "flex items-start gap-3 px-4 py-3 transition-colors",
                if(MapSet.member?(@selected_books, b.id), do: "bg-accent/10", else: "")
              ]}>
                <input
                  type="checkbox"
                  phx-click="toggle_book"
                  phx-value-id={b.id}
                  checked={MapSet.member?(@selected_books, b.id)}
                  class="ink-check mt-0.5"
                />
                <div class="min-w-0 flex-1">
                  <p class="text-fg font-medium break-words">{b.title}</p>
                  <p :if={b.series} class="text-xs text-muted truncate">{b.series.name}</p>
                  <p class="text-xs text-faint mt-0.5">
                    {b.library.name} · <.local_time id={"deleted-book-m-#{b.id}"} value={b.deleted_at} format="datetime" />
                  </p>
                  <p :if={first_path(b)} class="text-xs text-faint font-mono truncate mt-0.5" title={first_path(b)}>
                    {first_path(b)}
                  </p>
                  <div class="flex gap-2 mt-2">
                    <.book_actions book={b} />
                  </div>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Desktop table — hidden below sm --%>
          <div class="hidden sm:block bg-surface rounded-lg ring-1 ring-edge overflow-hidden">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-fg/10">
                  <th class="px-4 py-3 w-8">
                    <input
                      type="checkbox"
                      phx-click="select_all_books"
                      checked={all_books_selected}
                      class="ink-check"
                    />
                  </th>
                  <th class="px-4 py-3 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-muted">
                    {gettext("Title")}
                  </th>
                  <th class="px-4 py-3 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-muted">
                    {gettext("Series")}
                  </th>
                  <th class="hidden md:table-cell px-4 py-3 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-muted">
                    {gettext("Library")}
                  </th>
                  <th class="hidden xl:table-cell px-4 py-3 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-muted">
                    {gettext("Path")}
                  </th>
                  <th class="hidden lg:table-cell px-4 py-3 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-muted">
                    {gettext("Deleted")}
                  </th>
                  <th class="px-4 py-3"></th>
                </tr>
              </thead>
              <tbody>
                <%= for b <- @deleted_books do %>
                  <tr class={[
                    "border-b border-fg/10 last:border-0 transition-colors",
                    if(MapSet.member?(@selected_books, b.id), do: "bg-accent/10", else: "")
                  ]}>
                    <td class="px-4 py-3">
                      <input
                        type="checkbox"
                        phx-click="toggle_book"
                        phx-value-id={b.id}
                        checked={MapSet.member?(@selected_books, b.id)}
                        class="ink-check"
                      />
                    </td>
                    <td class="px-4 py-3 text-fg">{b.title}</td>
                    <td class="px-4 py-3 text-muted">
                      {if b.series, do: b.series.name, else: "—"}
                    </td>
                    <td class="hidden md:table-cell px-4 py-3 text-muted">{b.library.name}</td>
                    <td
                      class="hidden xl:table-cell px-4 py-3 text-muted text-xs font-mono truncate max-w-xs"
                      title={first_path(b)}
                    >
                      {first_path(b)}
                    </td>
                    <td class="hidden lg:table-cell px-4 py-3 text-muted text-xs whitespace-nowrap">
                      <.local_time id={"deleted-book-#{b.id}"} value={b.deleted_at} format="datetime" />
                    </td>
                    <td class="px-4 py-3">
                      <div class="flex gap-3 justify-end">
                        <.book_actions book={b} />
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :series, :any, required: true

  defp series_actions(assigns) do
    ~H"""
    <.ink_button variant="ghost" size="md" phx-click="restore_series" phx-value-id={@series.id}>
      {gettext("Restore")}
    </.ink_button>
    <.ink_button
      variant="danger"
      size="md"
      phx-click="show_confirm"
      phx-value-event="purge_series"
      phx-value-id={@series.id}
      phx-value-title={gettext("Purge Series")}
      phx-value-message={
        gettext(
          "Permanently delete \"%{name}\" and all its books? Book files on disk are never deleted. This cannot be undone.",
          name: @series.name
        )
      }
      phx-value-label={gettext("Purge")}
    >
      {gettext("Purge")}
    </.ink_button>
    """
  end

  attr :book, :any, required: true

  defp book_actions(assigns) do
    ~H"""
    <.ink_button variant="ghost" size="md" phx-click="restore_book" phx-value-id={@book.id}>
      {gettext("Restore")}
    </.ink_button>
    <.ink_button
      variant="danger"
      size="md"
      phx-click="show_confirm"
      phx-value-event="purge_book"
      phx-value-id={@book.id}
      phx-value-title={gettext("Purge Book")}
      phx-value-message={
        gettext(
          "Permanently delete \"%{name}\"? Book files on disk are never deleted. This cannot be undone.",
          name: @book.title
        )
      }
      phx-value-label={gettext("Purge")}
    >
      {gettext("Purge")}
    </.ink_button>
    """
  end

  defp first_path(book), do: book.files |> List.first() |> then(&(&1 && &1.path))
end
