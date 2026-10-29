# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.MetadataEditComponents do
  @moduledoc """
  Building blocks of the book and series edit dialogs: tabs, a labelled field
  with a lock toggle, removable chips and editable rows.

  The dialogs keep their draft in the LiveComponent; every control is a plain
  form input named `<prefix>[key]…`, so the form's `phx-change` carries the
  whole draft. Lists are indexed (`book[credits][0][creator]`). A locked field
  renders read-only; see `Stashix.Metadata.Locks`.
  """
  use Phoenix.Component

  import StashixWeb.UI.Icon
  import StashixWeb.UI.Forms, only: [input_class: 1]
  import StashixWeb.UI.Ink, only: [eyebrow: 1]

  @doc "Tab bar; `tabs` is `[{key, label}]`."
  attr :tabs, :list, required: true
  attr :current, :string, required: true
  attr :target, :any, required: true

  def edit_tabs(assigns) do
    ~H"""
    <div role="tablist" class="flex flex-wrap gap-1 -mx-1 mb-4 border-b border-fg/10 pb-2">
      <button
        :for={{key, label} <- @tabs}
        type="button"
        role="tab"
        aria-selected={to_string(key == @current)}
        phx-click="tab"
        phx-value-tab={key}
        phx-target={@target}
        class={[
          "px-2.5 py-1 rounded-sm text-xs font-display font-bold uppercase tracking-wide transition-colors",
          if(key == @current, do: "bg-ink text-gray-950 -rotate-1", else: "text-fg-soft hover:text-fg hover:bg-fg/10")
        ]}
      >
        {label}
      </button>
    </div>
    """
  end

  @doc "A tab's panel. Hidden panels stay in the form so their inputs are submitted."
  attr :tab, :string, required: true
  attr :current, :string, required: true
  slot :inner_block, required: true

  def edit_panel(assigns) do
    ~H"""
    <div role="tabpanel" hidden={@tab != @current} class="grid grid-cols-2 gap-x-4 gap-y-3">
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc "Label with a lock toggle, and the control(s) for one field."
  attr :label, :string, required: true
  attr :key, :string, required: true
  attr :locks, :list, required: true
  attr :target, :any, required: true
  attr :class, :any, default: nil
  attr :hint, :string, default: nil
  slot :inner_block, required: true

  def edit_field(assigns) do
    assigns = assign(assigns, :locked, assigns.key in assigns.locks)

    ~H"""
    <div class={@class}>
      <div class="flex items-center justify-between gap-2 mb-1.5">
        <.eyebrow tag="span" size="sm" tone="light">{@label}</.eyebrow>
        <button
          type="button"
          phx-click="toggle_lock"
          phx-value-field={@key}
          phx-target={@target}
          aria-pressed={to_string(@locked)}
          aria-label={if @locked, do: "Unlock #{@label}", else: "Lock #{@label}"}
          title={
            if @locked,
              do: "Locked: rescans and matching leave it alone. Click to unlock.",
              else: "Lock so rescans and matching can't change it"
          }
          class={[
            "p-0.5 rounded-sm transition-colors",
            if(@locked, do: "text-ink", else: "text-faint hover:text-fg-soft")
          ]}
        >
          <.icon name={if @locked, do: "lucide-lock", else: "lucide-lock-open"} class="w-3.5 h-3.5" />
        </button>
      </div>
      {render_slot(@inner_block)}
      <p :if={@hint} class="mt-1.5 text-xs text-muted">{@hint}</p>
    </div>
    """
  end

  @doc "Text input that turns read-only when locked."
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :locked, :boolean, default: false
  attr :type, :string, default: "text"
  attr :size, :string, default: "md"
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(placeholder min max step inputmode)

  def edit_input(assigns) do
    ~H"""
    <input
      type={@type}
      name={@name}
      value={@value}
      readonly={@locked}
      phx-debounce="250"
      class={[input_class(@size), @locked && "opacity-60 cursor-not-allowed", @class]}
      {@rest}
    />
    """
  end

  @doc "Textarea that turns read-only when locked."
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :locked, :boolean, default: false
  attr :rows, :any, default: 3

  def edit_textarea(assigns) do
    ~H"""
    <textarea
      name={@name}
      rows={@rows}
      readonly={@locked}
      phx-debounce="250"
      class={[input_class("md"), "leading-relaxed", @locked && "opacity-60 cursor-not-allowed"]}
    >{@value}</textarea>
    """
  end

  @doc """
  Native select (dialog rows need many of them, and ink_select's popover
  menus don't fit inside scrolling rows). Locked: shows the label read-only.
  """
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :options, :list, required: true
  attr :locked, :boolean, default: false
  attr :prompt, :string, default: nil
  attr :size, :string, default: "md"
  attr :class, :any, default: nil

  def edit_select(assigns) do
    assigns = assign(assigns, :value, to_string(assigns.value || ""))

    ~H"""
    <%= if @locked do %>
      <input type="hidden" name={@name} value={@value} />
      <div class={[input_class(@size), "opacity-60 cursor-not-allowed truncate", @class]}>
        {Enum.find_value(@options, @prompt || "—", fn {label, v} -> to_string(v) == @value && label end)}
      </div>
    <% else %>
      <select name={@name} class={[input_class(@size), @class]}>
        <option :if={@prompt} value="">{@prompt}</option>
        <option :for={{label, v} <- @options} value={v} selected={to_string(v) == @value}>{label}</option>
      </select>
    <% end %>
    """
  end

  @doc "Searchable language picker (BCP 47 codes). Locked: shows the language read-only."
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :locked, :boolean, default: false

  def edit_language(assigns) do
    assigns = assign(assigns, :options, Stashix.Formatters.language_options(assigns.value))

    ~H"""
    <%= if @locked do %>
      <input type="hidden" name={@name} value={@value} />
      <div class={[input_class("md"), "opacity-60 cursor-not-allowed truncate"]}>
        {Stashix.Formatters.language_name(@value) || "—"}
      </div>
    <% else %>
      <StashixWeb.UI.Menu.ink_select
        id={@id}
        name={@name}
        label="Language"
        variant="field"
        value={@value}
        prompt="Unknown"
        options={@options}
        searchable
      />
    <% end %>
    """
  end

  @doc """
  Removable chips for a list of names, plus an add box (Enter adds). Each chip
  carries `<name>[i][name]` and, when known, `[external_id]`.
  """
  attr :name, :string, required: true
  attr :key, :string, required: true
  attr :items, :list, required: true
  attr :locked, :boolean, default: false
  attr :target, :any, required: true
  attr :nonce, :integer, default: 0
  attr :placeholder, :string, default: "Add… (Enter)"

  def edit_chips(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-1.5">
      <span
        :for={{item, i} <- Enum.with_index(@items)}
        class="inline-flex items-center gap-1 rounded-sm bg-fg/[0.06] border border-line px-2 py-0.5 text-xs text-fg"
      >
        <input type="hidden" name={"#{@name}[#{i}][name]"} value={item["name"]} />
        <input :if={item["external_id"]} type="hidden" name={"#{@name}[#{i}][external_id]"} value={item["external_id"]} />
        {item["name"]}
        <button
          :if={!@locked}
          type="button"
          phx-click="item_remove"
          phx-value-field={@key}
          phx-value-index={i}
          phx-target={@target}
          aria-label={"Remove #{item["name"]}"}
          class="text-faint hover:text-danger"
        >
          <.icon name="lucide-x" class="w-3 h-3" />
        </button>
      </span>
      <span :if={@locked and @items == []} class="text-xs text-muted">None</span>
      <%!-- form="" detaches the box from the form: Enter adds a chip instead of saving. --%>
      <input
        :if={!@locked}
        id={"chip-add-#{@key}-#{@nonce}"}
        type="text"
        form=""
        placeholder={@placeholder}
        autocomplete="off"
        phx-keydown="chip_add"
        phx-key="Enter"
        phx-value-field={@key}
        phx-target={@target}
        class={[input_class("sm"), "!w-40"]}
      />
    </div>
    """
  end

  @doc "Editable rows; the slot renders one row's inputs and gets `{row, index}`."
  attr :key, :string, required: true
  attr :rows, :list, required: true
  attr :locked, :boolean, default: false
  attr :target, :any, required: true
  attr :add_label, :string, default: "Add"
  slot :inner_block, required: true

  def edit_rows(assigns) do
    ~H"""
    <div class="space-y-1.5">
      <div :for={{row, i} <- Enum.with_index(@rows)} class="flex items-center gap-1.5">
        {render_slot(@inner_block, {row, i})}
        <button
          :if={!@locked}
          type="button"
          phx-click="item_remove"
          phx-value-field={@key}
          phx-value-index={i}
          phx-target={@target}
          aria-label="Remove row"
          class="p-1 text-faint hover:text-danger flex-shrink-0"
        >
          <.icon name="lucide-x" class="w-3.5 h-3.5" />
        </button>
      </div>
      <span :if={@locked and @rows == []} class="text-xs text-muted">None</span>
      <button
        :if={!@locked}
        type="button"
        phx-click="row_add"
        phx-value-field={@key}
        phx-target={@target}
        class="inline-flex items-center gap-1 text-xs text-fg-soft hover:text-fg"
      >
        <.icon name="lucide-plus" class="w-3.5 h-3.5" /> {@add_label}
      </button>
    </div>
    """
  end

  ## Draft helpers shared by the dialogs

  @doc "Indexed form params (`%{\"0\" => …, \"1\" => …}`) in order."
  def indexed(nil), do: []
  def indexed(list) when is_list(list), do: list

  def indexed(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {i, _} -> String.to_integer(i) end)
    |> Enum.map(&elem(&1, 1))
  end

  def blank_to_nil(nil), do: nil

  def blank_to_nil(s) when is_binary(s) do
    case String.trim(s) do
      "" -> nil
      t -> t
    end
  end

  def blank_to_nil(v), do: v
end
