defmodule StashixWeb.UI.Menu do
  @moduledoc """
  Menus, selects and segmented controls of the "ink" design language.

  `ink_menu/1` and `ink_select/1` share one client hook (`InkMenu`, in
  `assets/js/hooks/ink_menu.js`): opening, placement and keyboard handling are
  client-side, so a menu needs no assigns or events of its own.
  Specimens live at `/dev/ui`.
  """
  use Phoenix.Component

  import StashixUi.Icon, only: [icon: 1]

  @link_attrs ~w(navigate patch href replace method download target rel)

  @panel_class "ink-menu m-0 p-1.5 rounded-md bg-zinc-950 text-gray-100 ring-1 ring-white/15 overflow-y-auto overscroll-contain"

  @doc """
  Dropdown menu. The `:trigger` slot is the content of the button that opens
  it; style that button with the slot's `class`. Fill the menu with
  `menu_label/1`, `menu_item/1` and `menu_separator/1`, or any markup.

      <.ink_menu id="user-menu">
        <:trigger class="..." label="Account">…</:trigger>
        <.menu_item icon="lucide-log-out" phx-click="logout">Sign out</.menu_item>
      </.ink_menu>

  `modal` makes the click that dismisses the menu stop there instead of also
  reaching what is under it.
  """
  attr :id, :string, required: true
  attr :align, :string, default: "end", values: ~w(start end)
  attr :modal, :boolean, default: false
  attr :class, :any, default: nil, doc: "wrapper around the trigger"
  attr :panel_class, :any, default: "min-w-48"

  slot :trigger, required: true do
    attr :class, :any
    attr :label, :string, doc: "accessible name, for icon-only triggers"
    attr :title, :string
  end

  slot :inner_block, required: true

  def ink_menu(assigns) do
    assigns = assign(assigns, base: @panel_class)

    ~H"""
    <div id={@id} phx-hook="InkMenu" data-modal={@modal} class={["relative inline-flex", @class]}>
      <button
        :for={trigger <- @trigger}
        type="button"
        id={"#{@id}-trigger"}
        data-menu-trigger
        aria-haspopup="menu"
        aria-expanded="false"
        aria-controls={"#{@id}-panel"}
        aria-label={trigger[:label]}
        title={trigger[:title]}
        class={trigger[:class]}
      >
        {render_slot(trigger)}
      </button>
      <div
        id={"#{@id}-panel"}
        popover="manual"
        role="menu"
        tabindex="-1"
        aria-labelledby={"#{@id}-trigger"}
        data-menu-panel
        data-align={@align}
        class={[@base, @panel_class]}
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc "Tracked heading for a group of menu items."
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def menu_label(assigns) do
    ~H"""
    <p class={["ink-menu-label", @class]}>{render_slot(@inner_block)}</p>
    """
  end

  @doc """
  Row in an `ink_menu/1`. A link when given `navigate`, `patch` or `href`, a
  button otherwise (use `phx-click`). Choosing an item closes the menu unless
  `keep_open` is set.

  Pass `active` (true or false) for items that are one of several choices: the
  current one gets the ink bar and a check.
  """
  attr :icon, :string, default: nil
  attr :icon_class, :string, default: nil
  attr :active, :boolean, default: nil
  attr :tone, :string, default: "default", values: ~w(default warning danger)
  attr :keep_open, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global, include: @link_attrs ++ ~w(disabled)
  slot :inner_block, required: true

  def menu_item(assigns) do
    assigns =
      assign(assigns,
        link?: Enum.any?(~w(navigate patch href)a, &Map.has_key?(assigns.rest, &1)),
        role: if(is_nil(assigns.active), do: "menuitem", else: "menuitemradio"),
        item_class: [item_class(assigns.active == true, assigns.tone), assigns.class]
      )

    ~H"""
    <.link
      :if={@link?}
      role={@role}
      aria-checked={@active != nil && to_string(@active)}
      data-menu-item
      data-keep-open={@keep_open}
      class={@item_class}
      {@rest}
    >
      <.item_body icon={@icon} icon_class={@icon_class} tone={@tone}>
        {render_slot(@inner_block)}
      </.item_body>
    </.link>
    <button
      :if={!@link?}
      type="button"
      role={@role}
      aria-checked={@active != nil && to_string(@active)}
      data-menu-item
      data-keep-open={@keep_open}
      class={@item_class}
      {@rest}
    >
      <.item_body icon={@icon} icon_class={@icon_class} tone={@tone}>
        {render_slot(@inner_block)}
      </.item_body>
    </button>
    """
  end

  attr :icon, :string, default: nil
  attr :icon_class, :string, default: nil
  attr :tone, :string, default: "default"
  slot :inner_block, required: true

  defp item_body(assigns) do
    ~H"""
    <.icon
      :if={@icon}
      name={@icon}
      class={"ink-menu-icon w-4 h-4 flex-shrink-0 #{if @tone == "default", do: "text-gray-500"} #{@icon_class}"}
    />
    <span class="flex-1 min-w-0 truncate font-display font-bold uppercase tracking-wide">
      {render_slot(@inner_block)}
    </span>
    <.icon name="lucide-check" class="ink-menu-check w-3.5 h-3.5 flex-shrink-0 text-ink" />
    """
  end

  defp item_class(active, tone) do
    [
      "ink-menu-item w-full flex items-center gap-3 px-2 py-2 rounded-sm text-sm text-left outline-none transition-colors disabled:opacity-40 disabled:pointer-events-none",
      active && "is-active",
      case tone do
        "default" ->
          "text-gray-300 hover:text-white focus:text-white hover:bg-white/[0.05] focus:bg-white/[0.07]"

        "warning" ->
          "text-amber-300 hover:text-amber-200 focus:text-amber-200 hover:bg-amber-400/10 focus:bg-amber-400/10"

        "danger" ->
          "text-red-300 hover:text-red-200 focus:text-red-200 hover:bg-red-500/10 focus:bg-red-500/15"
      end
    ]
  end

  @doc "Hairline between groups of menu items."
  def menu_separator(assigns) do
    ~H"""
    <div role="separator" class="my-1.5 -mx-1.5 h-px bg-white/10"></div>
    """
  end

  @doc """
  Replacement for a native `<select>`: a button showing the current option
  that opens an ink menu of all of them. Carries its value in a hidden input
  named `name`, and fires the surrounding form's `phx-change` when it changes.

  `options` is a list of `{label, value}`. `prompt` adds a leading option with
  an empty value. `searchable` adds a box that narrows long lists.

  Looks: `pill` (rounded, for toolbars) or `field` (full width, for forms).
  """
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :options, :list, required: true
  attr :prompt, :string, default: nil
  attr :label, :string, default: nil, doc: "accessible name"
  attr :variant, :string, default: "pill", values: ~w(pill field)
  attr :size, :string, default: "md", values: ~w(sm md)
  attr :searchable, :boolean, default: false
  attr :align, :string, default: "end", values: ~w(start end)
  attr :form, :string, default: nil, doc: "id of the form, when the select sits outside it"
  attr :class, :any, default: nil

  def ink_select(assigns) do
    value = to_string(assigns.value || "")

    options =
      for {label, option_value} <- assigns.options, do: {to_string(label), to_string(option_value)}

    options = if assigns.prompt, do: [{assigns.prompt, ""} | options], else: options

    current =
      Enum.find_value(options, fn {label, v} -> v == value && label end) ||
        assigns.prompt || options |> List.first({"", ""}) |> elem(0)

    assigns = assign(assigns, value: value, options: options, current: current, base: @panel_class)

    ~H"""
    <div
      id={@id}
      phx-hook="InkMenu"
      data-select
      data-value={@value}
      data-clearable={@prompt != nil}
      data-has-value={@prompt != nil and @value != ""}
      class={["ink-select relative", if(@variant == "field", do: "flex w-full", else: "inline-flex"), @class]}
    >
      <input type="hidden" name={@name} value={@value} form={@form} data-select-input />
      <button
        type="button"
        id={"#{@id}-trigger"}
        data-menu-trigger
        aria-haspopup="listbox"
        aria-expanded="false"
        aria-controls={"#{@id}-panel"}
        aria-label={@label}
        class={select_trigger_class(@variant, @size)}
      >
        <span data-select-label class="flex-1 min-w-0 truncate text-left">{@current}</span>
        <.icon name="lucide-chevron-down" class="ink-select-chevron w-3.5 h-3.5 flex-shrink-0 transition-transform" />
      </button>
      <div
        id={"#{@id}-panel"}
        popover="manual"
        role="listbox"
        tabindex="-1"
        aria-label={@label}
        data-menu-panel
        data-match-width
        data-align={if @variant == "field", do: "start", else: @align}
        class={[@base, "max-w-[min(24rem,calc(100vw-1rem))]"]}
      >
        <div :if={@searchable} class="sticky -top-1.5 z-10 -mt-1.5 -mx-1.5 mb-1.5 p-1.5 bg-zinc-950">
          <%!-- form="" detaches the box from the surrounding form, so typing
               in it neither submits nor fires phx-change. --%>
          <input
            type="text"
            form=""
            data-menu-filter
            placeholder="Type to filter"
            aria-label="Filter options"
            autocomplete="off"
            class="w-full bg-gray-900 border border-gray-700 rounded-sm px-2.5 py-1.5 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-ink"
          />
        </div>
        <button
          :for={{label, option_value} <- @options}
          type="button"
          role="option"
          aria-selected={to_string(option_value == @value)}
          data-menu-item
          data-value={option_value}
          data-label={label}
          class={[
            "ink-menu-item w-full flex items-center gap-3 px-2 py-1.5 rounded-sm text-sm text-left text-gray-300 hover:text-white focus:text-white hover:bg-white/[0.05] focus:bg-white/[0.07] outline-none transition-colors",
            option_value == @value && "is-active"
          ]}
        >
          <span class="flex-1 min-w-0 truncate">{label}</span>
          <.icon name="lucide-check" class="ink-menu-check w-3.5 h-3.5 flex-shrink-0 text-ink" />
        </button>
        <p :if={@searchable} data-menu-empty hidden class="px-2 py-2 text-sm text-gray-500">No matches</p>
      </div>
    </div>
    """
  end

  defp select_trigger_class("pill", size),
    do: [
      "inline-flex items-center max-w-full font-medium rounded-full border bg-gray-900 border-gray-600 text-gray-100 hover:border-gray-400 focus-visible:outline-none focus-visible:border-ink cursor-pointer transition-colors",
      if(size == "sm", do: "gap-1.5 h-8 pl-3 pr-2.5 text-xs", else: "gap-2 h-9 pl-4 pr-3 text-sm")
    ]

  defp select_trigger_class("field", size),
    do: [
      "flex items-center w-full bg-gray-800 border border-gray-600 rounded-md text-gray-200 hover:border-gray-400 focus-visible:outline-none focus-visible:border-ink cursor-pointer transition-colors",
      if(size == "sm", do: "gap-1.5 pl-2 pr-1.5 py-1 text-xs", else: "gap-2 pl-2.5 pr-2 py-1.5 text-sm")
    ]

  @doc """
  Row (or column, with `vertical`) of joined `segment/1` cells.
  """
  attr :vertical, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def segmented(assigns) do
    ~H"""
    <div
      class={[
        "ink-segmented",
        if(@vertical, do: "flex-col divide-y divide-white/10", else: "divide-x divide-white/10"),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  One cell of a `segmented/1`: an icon, a short label, or both. `active` fills
  it violet; pass it only for cells that toggle or choose.
  """
  attr :active, :boolean, default: nil
  attr :icon, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(disabled title onclick)
  slot :inner_block

  def segment(assigns) do
    ~H"""
    <button
      type="button"
      aria-pressed={@active != nil && to_string(@active)}
      class={[segment_class(@active == true), @class]}
      {@rest}
    >
      <.icon :if={@icon} name={@icon} class="w-4 h-4 flex-shrink-0" />
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc "Class of a `segment/1`, for cells that cannot be one (a menu trigger inside a `segmented/1`)."
  def segment_class(active) do
    [
      "flex items-center justify-center h-8 min-w-8 px-2 transition-colors",
      if(active, do: "bg-violet-600 text-white", else: "text-gray-300 hover:text-white hover:bg-white/10")
    ]
  end
end
