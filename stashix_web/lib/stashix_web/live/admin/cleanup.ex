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
      <.display_heading level={1} class="text-4xl!">Cleanup</.display_heading>
      <%!-- Series section --%>
      <div class="space-y-3">
        <div class="flex items-center justify-between">
          <h2 class="font-display font-black uppercase text-2xl leading-none text-white">
            Deleted Series <span class="ml-2 text-sm font-normal text-gray-400">({length(@deleted_series)})</span>
          </h2>
          <%= if series_sel_count > 0 do %>
            <div class="flex items-center gap-3">
              <span class="text-sm text-gray-400">{series_sel_count} selected</span>
              <.ink_button
                size="md"
                phx-click="batch_restore_series"
              >
                Restore Selected
              </.ink_button>
              <.ink_button
                variant="danger"
                size="md"
                phx-click="show_confirm"
                phx-value-event="batch_purge_series"
                phx-value-title="Purge Series"
                phx-value-message={"Permanently delete #{series_sel_count} series and ALL their books? Book files on disk are never deleted. This cannot be undone."}
                phx-value-label="Purge"
              >
                Purge Selected
              </.ink_button>
            </div>
          <% end %>
        </div>
        <%= if @deleted_series == [] do %>
          <p class="text-gray-400 text-sm">No deleted series.</p>
        <% else %>
          <div class="bg-gray-900 rounded-lg ring-1 ring-white/10 overflow-hidden">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-white/10">
                  <th class="px-4 py-3 w-8">
                    <input
                      type="checkbox"
                      phx-click="select_all_series"
                      checked={all_series_selected}
                      class="ink-check"
                    />
                  </th>
                  <th class="px-4 py-3 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">
                    Series
                  </th>
                  <th class="px-4 py-3 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">
                    Library
                  </th>
                  <th class="px-4 py-3 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">
                    Deleted
                  </th>
                  <th class="px-4 py-3"></th>
                </tr>
              </thead>
              <tbody>
                <%= for s <- @deleted_series do %>
                  <tr class={[
                    "border-b border-white/10 last:border-0 transition-colors",
                    if(MapSet.member?(@selected_series, s.id), do: "bg-violet-950/30", else: "")
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
                    <td class="px-4 py-3 text-white">{s.name}</td>
                    <td class="px-4 py-3 text-gray-400">{s.library.name}</td>
                    <td class="px-4 py-3 text-gray-400 text-xs">
                      {Calendar.strftime(s.deleted_at, "%Y-%m-%d %H:%M")}
                    </td>
                    <td class="px-4 py-3 text-right flex gap-3 justify-end">
                      <.ink_button variant="ghost" size="md" phx-click="restore_series" phx-value-id={s.id}>
                        Restore
                      </.ink_button>
                      <.ink_button
                        variant="danger"
                        size="md"
                        phx-click="show_confirm"
                        phx-value-event="purge_series"
                        phx-value-id={s.id}
                        phx-value-title="Purge Series"
                        phx-value-message={"Permanently delete \"#{s.name}\" and all its books? Book files on disk are never deleted. This cannot be undone."}
                        phx-value-label="Purge"
                      >
                        Purge
                      </.ink_button>
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
        <div class="flex items-center justify-between">
          <h2 class="font-display font-black uppercase text-2xl leading-none text-white">
            Deleted Books <span class="ml-2 text-sm font-normal text-gray-400">({length(@deleted_books)})</span>
          </h2>
          <%= if books_sel_count > 0 do %>
            <div class="flex items-center gap-3">
              <span class="text-sm text-gray-400">{books_sel_count} selected</span>
              <.ink_button
                size="md"
                phx-click="batch_restore_books"
              >
                Restore Selected
              </.ink_button>
              <.ink_button
                variant="danger"
                size="md"
                phx-click="show_confirm"
                phx-value-event="batch_purge_books"
                phx-value-title="Purge Books"
                phx-value-message={"Permanently delete #{books_sel_count} book(s)? Book files on disk are never deleted. This cannot be undone."}
                phx-value-label="Purge"
              >
                Purge Selected
              </.ink_button>
            </div>
          <% end %>
        </div>
        <%= if @deleted_books == [] do %>
          <p class="text-gray-400 text-sm">No deleted books.</p>
        <% else %>
          <div class="bg-gray-900 rounded-lg ring-1 ring-white/10 overflow-hidden">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-white/10">
                  <th class="px-4 py-3 w-8">
                    <input
                      type="checkbox"
                      phx-click="select_all_books"
                      checked={all_books_selected}
                      class="ink-check"
                    />
                  </th>
                  <th class="px-4 py-3 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">
                    Title
                  </th>
                  <th class="px-4 py-3 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">
                    Series
                  </th>
                  <th class="px-4 py-3 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">
                    Library
                  </th>
                  <th class="px-4 py-3 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">
                    Path
                  </th>
                  <th class="px-4 py-3 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">
                    Deleted
                  </th>
                  <th class="px-4 py-3"></th>
                </tr>
              </thead>
              <tbody>
                <%= for b <- @deleted_books do %>
                  <tr class={[
                    "border-b border-white/10 last:border-0 transition-colors",
                    if(MapSet.member?(@selected_books, b.id), do: "bg-violet-950/30", else: "")
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
                    <td class="px-4 py-3 text-white">{b.title}</td>
                    <td class="px-4 py-3 text-gray-400">
                      {if b.series, do: b.series.name, else: "—"}
                    </td>
                    <td class="px-4 py-3 text-gray-400">{b.library.name}</td>
                    <td
                      class="px-4 py-3 text-gray-400 text-xs font-mono truncate max-w-xs"
                      title={b.files |> List.first() |> then(&(&1 && &1.path))}
                    >
                      {b.files |> List.first() |> then(&(&1 && &1.path))}
                    </td>
                    <td class="px-4 py-3 text-gray-400 text-xs">
                      {Calendar.strftime(b.deleted_at, "%Y-%m-%d %H:%M")}
                    </td>
                    <td class="px-4 py-3 text-right flex gap-3 justify-end">
                      <.ink_button variant="ghost" size="md" phx-click="restore_book" phx-value-id={b.id}>
                        Restore
                      </.ink_button>
                      <.ink_button
                        variant="danger"
                        size="md"
                        phx-click="show_confirm"
                        phx-value-event="purge_book"
                        phx-value-id={b.id}
                        phx-value-title="Purge Book"
                        phx-value-message={"Permanently delete \"#{b.title}\"? Book files on disk are never deleted. This cannot be undone."}
                        phx-value-label="Purge"
                      >
                        Purge
                      </.ink_button>
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
end
