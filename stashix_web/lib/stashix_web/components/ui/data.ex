# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.UI.Data do
  @moduledoc """
  Tables and tab bars of the "ink" design language. Specimens live at `/dev/ui`.
  """
  use Phoenix.Component

  import StashixWeb.UI.Ink, only: [sticker: 1]

  @doc """
  Table in a plain panel. One `:col` per column; `:action` is a trailing,
  right-aligned cell for row buttons.

      <.data_table id="users" rows={@users}>
        <:col :let={user} label="Username">{user.username}</:col>
        <:action :let={user}><.ink_button …>Delete</.ink_button></:action>
      </.data_table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "function from a row to its DOM id"
  attr :class, :any, default: nil

  slot :col, required: true do
    attr :label, :string
    attr :align, :string, values: ~w(left right)
    attr :class, :any
  end

  slot :action
  slot :empty

  def data_table(assigns) do
    ~H"""
    <div class={["rounded-lg bg-surface ring-1 ring-edge overflow-x-auto", @class]}>
      <table id={@id} class="w-full text-sm text-left">
        <thead>
          <tr class="border-b border-fg/10">
            <th
              :for={col <- @col}
              scope="col"
              class={[
                "px-4 py-3 text-[10px] font-bold tracking-[0.18em] uppercase text-muted whitespace-nowrap",
                col[:align] == "right" && "text-right"
              ]}
            >
              {col[:label]}
            </th>
            <th :if={@action != []} scope="col" class="px-4 py-3"><span class="sr-only">Actions</span></th>
          </tr>
        </thead>
        <tbody class="divide-y divide-fg/[0.06]">
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="hover:bg-fg/[0.03] transition-colors">
            <td
              :for={col <- @col}
              class={["px-4 py-3 text-fg-soft", col[:align] == "right" && "text-right tabular-nums", col[:class]]}
            >
              {render_slot(col, row)}
            </td>
            <td :if={@action != []} class="px-4 py-3">
              <div class="flex items-center justify-end gap-2">{render_slot(@action, row)}</div>
            </td>
          </tr>
          <tr :if={@rows == [] and @empty != []}>
            <td colspan={length(@col) + if(@action != [], do: 1, else: 0)} class="px-4 py-8 text-center text-muted">
              {render_slot(@empty)}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Row of tabs in display type; the current one is an ink sticker. Each `:tab`
  links with `patch` or `navigate`; `count` adds a small figure. Tabs with
  counts wrap rather than scroll; on phones each stacks its count under the
  label and stretches to fill its row. Others scroll sideways.
  """
  attr :label, :string, required: true, doc: "accessible name of the tab bar"
  attr :class, :any, default: nil

  slot :tab, required: true do
    attr :patch, :string
    attr :navigate, :string
    attr :active, :boolean
    attr :count, :integer
  end

  def tabs(assigns) do
    assigns = assign(assigns, :stacked, Enum.any?(assigns.tab, & &1[:count]))

    ~H"""
    <nav
      aria-label={@label}
      class={[
        "pb-3 border-b border-fg/15",
        if(@stacked,
          do: "flex flex-wrap gap-1 sm:items-center sm:gap-2",
          else: "flex items-center gap-1 sm:gap-2 overflow-x-auto"
        ),
        @class
      ]}
    >
      <.link
        :for={tab <- @tab}
        patch={tab[:patch]}
        navigate={tab[:navigate]}
        aria-current={tab[:active] && "page"}
        class={[
          "rounded-sm font-display font-black uppercase leading-none whitespace-nowrap transition-colors",
          if(@stacked,
            do:
              "flex flex-auto flex-col items-center gap-1.5 px-1.5 pt-1.5 pb-1 text-lg sm:flex-none sm:flex-row sm:gap-2 sm:px-2.5 sm:pt-1 sm:pb-0.5 sm:text-2xl",
            else: "inline-flex items-center gap-2 px-2.5 pt-1 pb-0.5 text-2xl"
          ),
          if(tab[:active],
            do: "bg-ink text-gray-950 -rotate-1",
            else: "text-fg-soft hover:text-fg hover:bg-fg/10"
          )
        ]}
      >
        {render_slot(tab)}
        <.sticker
          :if={tab[:count] && tab[:count] > 0}
          size="xs"
          tilt={false}
          class={tab[:active] && "bg-canvas! text-ink!"}
        >
          {tab[:count]}
        </.sticker>
      </.link>
    </nav>
    """
  end
end
