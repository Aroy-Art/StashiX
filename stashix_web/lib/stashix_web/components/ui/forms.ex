defmodule StashixWeb.UI.Forms do
  @moduledoc """
  Form controls of the "ink" design language. Selects live in
  `StashixWeb.UI.Menu` (`ink_select/1`). Specimens live at `/dev/ui`.
  """
  use Phoenix.Component

  import StashixWeb.UI.Ink, only: [eyebrow: 1]

  @input_attrs ~w(name value type placeholder required disabled readonly autocomplete autofocus
                  min max step minlength maxlength pattern inputmode form list)

  @doc """
  Label, control and the small print under it. Wrap one control:

      <.field label="Name" hint="Shown on the cover.">
        <.text_input name="series[name]" value={@name} />
      </.field>

  The label wraps the control, so clicking it focuses the control without ids.
  """
  attr :label, :string, required: true
  attr :required, :boolean, default: false
  attr :hint, :string, default: nil
  attr :error, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def field(assigns) do
    ~H"""
    <div class={@class}>
      <label class="block">
        <.eyebrow tag="span" size="sm" tone="light" class="block mb-1.5">
          {@label}<span :if={@required} class="text-ink" aria-hidden="true"> *</span>
        </.eyebrow>
        {render_slot(@inner_block)}
      </label>
      <p :if={@hint && !@error} class="mt-1.5 text-xs text-gray-500">{@hint}</p>
      <p :if={@error} class="mt-1.5 text-xs font-medium text-red-300">{@error}</p>
    </div>
    """
  end

  @doc "Single-line input. `size=\"sm\"` for dense rows."
  attr :size, :string, default: "md", values: ~w(sm md)
  attr :mono, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global, include: @input_attrs

  def text_input(assigns) do
    ~H"""
    <input class={[input_class(@size), @mono && "font-mono", @class]} {@rest} />
    """
  end

  @doc "Multi-line input. The text goes in `value`."
  attr :value, :string, default: nil
  attr :rows, :any, default: 4
  attr :mono, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global, include: @input_attrs

  def textarea(assigns) do
    ~H"""
    <textarea rows={@rows} class={[input_class("md"), "leading-relaxed", @mono && "font-mono text-xs", @class]} {@rest}>{@value}</textarea>
    """
  end

  @doc "Class of a text control, for the rare control that cannot be one of the components."
  def input_class(size \\ "md") do
    [
      "block w-full rounded-md bg-gray-800 border border-gray-600 text-gray-100 placeholder:text-gray-500 hover:border-gray-400 focus:outline-none focus:border-ink disabled:opacity-50 transition-colors",
      if(size == "sm", do: "px-2 py-1 text-xs", else: "px-3 py-2 text-sm")
    ]
  end

  @doc """
  Checkbox with its label. With `unchecked_value` a hidden input is sent
  first, so the form always carries the field.
  """
  attr :name, :string, default: nil
  attr :value, :string, default: "true"
  attr :unchecked_value, :string, default: nil
  attr :checked, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(disabled form id)
  slot :inner_block

  def checkbox(assigns) do
    ~H"""
    <label class={["inline-flex items-center gap-2 text-sm text-gray-200 cursor-pointer select-none", @class]}>
      <input :if={@unchecked_value} type="hidden" name={@name} value={@unchecked_value} />
      <input type="checkbox" name={@name} value={@value} checked={@checked} class="ink-check" {@rest} />
      <span :if={@inner_block != []}>{render_slot(@inner_block)}</span>
    </label>
    """
  end

  @doc """
  On/off switch that acts at once (give it a `phx-click`). For a value that
  travels with a form, use `checkbox/1`.
  """
  attr :on, :boolean, required: true
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(disabled title)
  slot :inner_block

  def toggle(assigns) do
    ~H"""
    <button
      type="button"
      role="switch"
      aria-checked={to_string(@on)}
      class={[
        "group inline-flex items-center gap-2 text-xs font-medium text-gray-300 hover:text-white disabled:opacity-40 disabled:pointer-events-none transition-colors",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
      <span class={[
        "relative inline-flex h-5 w-9 flex-shrink-0 items-center rounded-full ring-1 transition-colors",
        if(@on, do: "bg-violet-600 ring-violet-400/60", else: "bg-gray-800 ring-white/20")
      ]}>
        <span class={[
          "inline-block h-3.5 w-3.5 rounded-full transition-transform",
          if(@on, do: "translate-x-[1.125rem] bg-ink", else: "translate-x-[0.1875rem] bg-gray-400")
        ]}></span>
      </span>
    </button>
    """
  end
end
