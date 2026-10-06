defmodule StashixWeb.UI.Ink do
  @moduledoc """
  Primitives of the "ink" design language: buttons, type, labels and panels.

  Components take a `class` for layout only (margins, position, responsive
  visibility). Looks are picked with attrs so the recipes stay in one place.
  Specimens of everything here live at `/dev/ui`.
  """
  use Phoenix.Component

  import StashixUi.Icon, only: [icon: 1]

  @link_attrs ~w(navigate patch href replace method download target rel)
  @button_attrs ~w(type disabled form name value)

  # ---------------------------------------------------------------------------
  # Buttons and links
  # ---------------------------------------------------------------------------

  @doc """
  Call-to-action in display type. Renders a link when given `navigate`, `patch`
  or `href`, a `<button>` otherwise.

  `primary` carries the hard ink offset shadow and is meant to appear once per
  view; `ghost` is the quiet companion next to it; `danger` is for destructive
  actions.
  """
  attr :variant, :string, default: "primary", values: ~w(primary ghost danger)
  attr :size, :string, default: "lg", values: ~w(md lg)
  attr :class, :any, default: nil
  attr :rest, :global, include: @link_attrs ++ @button_attrs
  slot :inner_block, required: true

  def ink_button(assigns) do
    ~H"""
    <.clickable class={[button_class(@variant, @size), @class]} {@rest}>
      {render_slot(@inner_block)}
    </.clickable>
    """
  end

  defp button_class("primary", size),
    do: [
      "ink-btn inline-flex items-center justify-center bg-violet-600 hover:bg-violet-500 text-white font-display font-extrabold uppercase tracking-wide rounded-md",
      primary_size(size)
    ]

  defp button_class("ghost", size),
    do: [
      "inline-flex items-center justify-center rounded-md ring-1 ring-white/15 bg-white/[0.04] hover:bg-white/[0.1] hover:ring-white/30 text-gray-200 hover:text-white font-display font-bold uppercase tracking-wide transition-colors",
      quiet_size(size)
    ]

  defp button_class("danger", size),
    do: [
      "inline-flex items-center justify-center rounded-md ring-1 ring-red-500/50 bg-red-500/10 hover:bg-red-500/25 hover:ring-red-400 text-red-300 hover:text-red-100 font-display font-bold uppercase tracking-wide transition-colors",
      quiet_size(size)
    ]

  defp primary_size("lg"), do: "gap-2.5 px-6 py-2.5 text-xl"
  defp primary_size("md"), do: "gap-2 px-4 py-1.5 text-base"
  defp quiet_size("lg"), do: "gap-2 px-4 py-2.5"
  defp quiet_size("md"), do: "gap-1.5 px-3 py-1.5 text-sm"

  @doc """
  Primary action joined to a second control (usually a menu trigger) under one
  shared ink shadow. The main half takes the link/button attrs; whatever goes
  in `:aside` is rendered flush against its right edge.
  """
  attr :class, :any, default: nil
  attr :rest, :global, include: @link_attrs ++ @button_attrs
  slot :inner_block, required: true
  slot :aside, required: true

  def split_button(assigns) do
    ~H"""
    <div class={["ink-split inline-flex items-stretch rounded-md", @class]}>
      <.clickable
        class="inline-flex items-center gap-2.5 px-6 py-2.5 bg-violet-600 hover:bg-violet-500 text-white font-display font-extrabold uppercase text-xl tracking-wide rounded-l-md transition-colors"
        {@rest}
      >
        {render_slot(@inner_block)}
      </.clickable>
      {render_slot(@aside)}
    </div>
    """
  end

  @doc "Class for the right half of a `split_button/1`."
  def split_aside_class,
    do:
      "flex items-center px-2.5 bg-violet-700 hover:bg-violet-600 text-white rounded-r-md border-l border-violet-400/40 transition-colors"

  @doc "Round glass button holding a single icon. `label` is the accessible name."
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :class, :any, default: nil
  attr :rest, :global, include: @link_attrs ++ @button_attrs

  def icon_button(assigns) do
    ~H"""
    <.clickable
      aria-label={@label}
      class={[
        "flex items-center justify-center w-8 h-8 rounded-full bg-white/5 hover:bg-white/15 text-gray-300 hover:text-white backdrop-blur-sm transition-colors flex-shrink-0",
        @class
      ]}
      {@rest}
    >
      <.icon name={@icon} class="w-4 h-4" />
    </.clickable>
    """
  end

  @doc """
  Underlined inline action. `accent` has the heavy violet underline used for
  "Show all" / "Clear all"; `subtle` is a thin white one for secondary links.
  """
  attr :tone, :string, default: "accent", values: ~w(accent subtle)
  attr :class, :any, default: nil
  attr :rest, :global, include: @link_attrs ++ @button_attrs
  slot :inner_block, required: true

  def text_link(assigns) do
    ~H"""
    <.clickable
      class={[
        "inline-flex items-center font-medium hover:text-white underline underline-offset-4 transition-colors",
        if(@tone == "accent",
          do: "gap-1.5 text-sm md:text-base text-gray-200 decoration-2 decoration-violet-500 hover:decoration-violet-300",
          else: "gap-2 text-sm text-gray-300 decoration-white/25 hover:decoration-white"
        ),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.clickable>
    """
  end

  # ---------------------------------------------------------------------------
  # Type and labels
  # ---------------------------------------------------------------------------

  @doc """
  Small tracked uppercase label that sits above a headline or names a section.

  Sizes: `md` (11px) over hero headlines and filter groups, `sm` (10px) for
  field and fact labels, `xs` (9px) inside dense detail grids.
  """
  attr :tag, :string, default: "p"
  attr :tone, :string, default: "violet", values: ~w(violet muted ink light)
  attr :size, :string, default: "md", values: ~w(xs sm md)
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def eyebrow(assigns) do
    ~H"""
    <.dynamic_tag
      tag_name={@tag}
      class={["font-bold uppercase", eyebrow_size(@size), eyebrow_tone(@tone), @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.dynamic_tag>
    """
  end

  defp eyebrow_size("md"), do: "text-[11px] tracking-[0.2em]"
  defp eyebrow_size("sm"), do: "text-[10px] tracking-[0.18em]"
  defp eyebrow_size("xs"), do: "text-[9px] tracking-[0.14em]"

  defp eyebrow_tone("violet"), do: "text-violet-300"
  defp eyebrow_tone("muted"), do: "text-gray-500"
  defp eyebrow_tone("ink"), do: "text-ink/80"
  defp eyebrow_tone("light"), do: "text-gray-300"

  @doc """
  Heading in the display face. `hero` is the page title, `section` heads a
  block of content, `panel` heads a side panel. `count` adds a trailing figure.
  """
  attr :level, :integer, default: 2, values: [1, 2, 3]
  attr :size, :string, default: "section", values: ~w(hero section panel)
  attr :count, :any, default: nil
  attr :count_tone, :string, default: "muted", values: ~w(muted ink)
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def display_heading(assigns) do
    ~H"""
    <.dynamic_tag
      tag_name={"h#{@level}"}
      class={["font-display font-black uppercase text-white", heading_size(@size), @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
      <span
        :if={@count}
        class={["tabular-nums", if(@count_tone == "ink", do: "text-ink", else: "text-gray-500")]}
      >
        {@count}
      </span>
    </.dynamic_tag>
    """
  end

  defp heading_size("hero"), do: "text-5xl md:text-7xl leading-[0.88] text-balance break-words"
  defp heading_size("section"), do: "text-3xl leading-none"
  defp heading_size("panel"), do: "text-2xl leading-none"

  @doc """
  Oversized outlined figure that sits behind a hero. Decorative: hidden from
  assistive tech and from the pointer. Size and position come from `class`.
  """
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def ghost_numeral(assigns) do
    ~H"""
    <span class={["ghost-numeral pointer-events-none", @class]} aria-hidden="true">
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc "Ink label in black display type: issue numbers, counts. Tilted unless `tilt` is false."
  attr :size, :string, default: "sm", values: ~w(xs sm md lg)
  attr :tilt, :boolean, default: true
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def sticker(assigns) do
    ~H"""
    <span
      class={[
        "inline-block bg-ink text-zinc-950 font-display font-black rounded-sm tabular-nums",
        sticker_size(@size),
        @tilt && "sticker",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp sticker_size("xs"), do: "px-1.5 text-xs leading-normal"
  defp sticker_size("sm"), do: "px-1.5 text-base leading-tight"
  defp sticker_size("md"), do: "px-2.5 py-0.5 text-lg leading-tight uppercase"
  defp sticker_size("lg"), do: "px-2 pt-0.5 text-2xl leading-none"

  @doc "Keyboard hint: one key cap per entry in `keys`."
  attr :keys, :list, required: true
  attr :class, :any, default: nil

  def kbd(assigns) do
    ~H"""
    <kbd class={["inline-flex items-center gap-1 pointer-events-none", @class]}>
      <span
        :for={key <- @keys}
        class="text-[10px] font-semibold text-gray-300 bg-gray-900/80 border border-white/20 rounded px-1.5 py-0.5 leading-none"
      >
        {key}
      </span>
    </kbd>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global, include: @link_attrs ++ @button_attrs
  slot :inner_block, required: true

  defp clickable(assigns) do
    assigns = assign(assigns, link?: Enum.any?(~w(navigate patch href)a, &Map.has_key?(assigns.rest, &1)))

    ~H"""
    <.link :if={@link?} class={@class} {@rest}>{render_slot(@inner_block)}</.link>
    <button :if={!@link?} class={@class} {@rest}>{render_slot(@inner_block)}</button>
    """
  end
end
