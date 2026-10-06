defmodule StashixWeb.Dev.UiLive do
  @moduledoc """
  Style guide for the "ink" design language, mounted at `/dev/ui` when
  `dev_routes` is on. Every shared component gets a specimen here in every
  variant; add one whenever a component is added (see docs/ui-redesign-plan.md).
  """
  use StashixWeb, :live_view

  import StashixWeb.DetailComponents

  @colors [
    {"background", "bg-gray-950", "gray-950 — page"},
    {"panel", "bg-gray-900", "gray-900 — panels"},
    {"menu", "bg-zinc-950", "zinc-950 — menus, reader bars"},
    {"action", "bg-violet-600", "violet-600 — primary action"},
    {"ink", "bg-ink", "ink — second highlight"},
    {"eyebrow", "bg-violet-300", "violet-300 — eyebrows"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "UI", colors: @colors, segment: "page", menu_value: "single")}
  end

  @impl true
  def handle_event("set_segment", %{"value" => value}, socket), do: {:noreply, assign(socket, segment: value)}
  def handle_event("set_menu", %{"value" => value}, socket), do: {:noreply, assign(socket, menu_value: value)}

  attr :title, :string, required: true
  attr :note, :string, default: nil
  slot :inner_block, required: true

  defp specimen(assigns) do
    ~H"""
    <section class="space-y-4">
      <div class="flex items-baseline gap-4 border-b border-white/10 pb-2">
        <h2 class="font-display font-black uppercase text-3xl leading-none text-white">{@title}</h2>
        <p :if={@note} class="text-xs text-gray-500">{@note}</p>
      </div>
      <div class="flex flex-wrap items-center gap-6">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.detail_page wide>
      <header class="relative pt-2">
        <span
          class="ghost-numeral hidden sm:block absolute -top-2 right-0 text-[9rem] pointer-events-none"
          aria-hidden="true"
        >
          UI
        </span>
        <p class="rise text-[11px] font-bold tracking-[0.2em] uppercase text-violet-300 mb-3" style="--i:1">
          Dev only
        </p>
        <h1 class="rise font-display font-black uppercase text-5xl md:text-7xl leading-[0.88] text-white" style="--i:2">
          Style guide
        </h1>
      </header>

      <.specimen title="Colour">
        <div :for={{name, class, note} <- @colors} class="w-40">
          <div class={["h-14 rounded-md ring-1 ring-white/15", class]}></div>
          <p class="mt-2 text-[10px] font-bold tracking-[0.18em] uppercase text-ink/80">{name}</p>
          <p class="text-xs text-gray-400">{note}</p>
        </div>
      </.specimen>

      <.specimen title="Type">
        <div class="space-y-3">
          <p class="text-[11px] font-bold tracking-[0.2em] uppercase text-violet-300">Eyebrow</p>
          <p class="font-display font-black uppercase text-6xl leading-[0.88] text-white">Hero headline</p>
          <p class="font-display font-black uppercase text-3xl leading-none text-white">
            Section heading <span class="text-gray-600 tabular-nums">12</span>
          </p>
          <p class="text-[15px] text-gray-300 leading-7 max-w-xl">
            Body copy sits in the system sans at 15px on a relaxed leading, gray-300 on the page background.
          </p>
          <a class="inline-flex items-center gap-1.5 text-sm font-medium text-gray-200 hover:text-white underline decoration-2 decoration-violet-500 hover:decoration-violet-300 underline-offset-4 transition-colors">
            Text link <.icon name="lucide-arrow-right" class="w-4 h-4 text-ink" />
          </a>
        </div>
      </.specimen>

      <.specimen title="Buttons" note=".ink-btn, .ink-split">
        <button class="ink-btn inline-flex items-center gap-2.5 px-6 py-2.5 bg-violet-600 hover:bg-violet-500 text-white font-display font-extrabold uppercase text-xl tracking-wide rounded-md">
          <.icon name="lucide-play" class="w-4 h-4" /> Continue <span class="text-ink">#4</span>
        </button>
        <button class="inline-flex items-center gap-2 px-4 py-2.5 rounded-md ring-1 ring-white/15 bg-white/[0.04] hover:bg-white/[0.1] hover:ring-white/30 text-gray-200 hover:text-white font-display font-bold uppercase tracking-wide transition-colors">
          <.icon name="lucide-book-open" class="w-4 h-4" /> Ghost
        </button>
        <div class="ink-split inline-flex items-stretch rounded-md">
          <button class="inline-flex items-center gap-2.5 px-6 py-2.5 bg-violet-600 hover:bg-violet-500 text-white font-display font-extrabold uppercase text-xl tracking-wide rounded-l-md transition-colors">
            <.icon name="lucide-play" class="w-4 h-4" /> Read
          </button>
          <button
            class="flex items-center px-2.5 bg-violet-700 hover:bg-violet-600 text-white rounded-r-md border-l border-violet-400/40 transition-colors"
            aria-label="More"
          >
            <.icon name="lucide-chevron-down" class="w-4 h-4" />
          </button>
        </div>
        <button
          class="flex items-center justify-center w-8 h-8 rounded-full bg-white/5 hover:bg-white/15 text-gray-300 hover:text-white transition-colors"
          aria-label="Icon button"
        >
          <.icon name="lucide-arrow-left" class="w-4 h-4" />
        </button>
      </.specimen>

      <.specimen title="Stickers and pills" note=".sticker">
        <span class="sticker px-1.5 bg-ink text-zinc-950 font-display font-black text-base leading-tight rounded-sm tabular-nums">
          #12
        </span>
        <span class="px-2.5 py-1 text-xs rounded-full border bg-ink border-ink text-gray-950 font-semibold">Selected pill</span>
        <span class="px-2.5 py-1 text-xs rounded-full border bg-gray-800 border-gray-600 text-gray-200">Pill</span>
        <span class="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full bg-white/5 border border-white/15 text-xs text-gray-200">
          Chip <span class="text-gray-500">3</span>
        </span>
        <span class="inline-flex items-center gap-1 pl-2.5 pr-1 py-0.5 rounded-sm bg-gray-950 border border-ink/70 text-xs font-semibold text-ink">
          Picked <.icon name="lucide-x" class="w-3.5 h-3.5" />
        </span>
      </.specimen>

      <.specimen title="Segmented control" note=".ink-segmented">
        <div class="ink-segmented divide-x divide-white/10">
          <button
            :for={
              {value, icon} <- [
                {"page", "lucide-scan"},
                {"width", "lucide-move-horizontal"},
                {"height", "lucide-move-vertical"}
              ]
            }
            phx-click="set_segment"
            phx-value-value={value}
            aria-pressed={to_string(@segment == value)}
            class={[
              "flex items-center justify-center h-8 min-w-8 px-2 transition-colors",
              if(@segment == value,
                do: "bg-violet-600 text-white",
                else: "text-gray-300 hover:text-white hover:bg-white/10"
              )
            ]}
          >
            <.icon name={icon} class="w-4 h-4" />
          </button>
        </div>
      </.specimen>

      <.specimen title="Menu" note=".ink-menu — becomes <.ink_menu> in Phase 2">
        <div class="ink-menu w-60 p-1.5 rounded-md bg-zinc-950 ring-1 ring-white/15">
          <p class="ink-menu-label">Layout</p>
          <button
            :for={
              {value, label, icon} <- [
                {"single", "Single page", "lucide-rectangle-vertical"},
                {"double", "Facing pages", "lucide-columns-2"},
                {"cover", "Facing, cover first", "lucide-layout-panel-top"}
              ]
            }
            phx-click="set_menu"
            phx-value-value={value}
            class={[
              "ink-menu-item w-full flex items-center gap-3 px-2 py-2 rounded-sm text-sm text-left transition-colors",
              if(@menu_value == value,
                do: "is-active bg-white/[0.07] text-white",
                else: "text-gray-300 hover:text-white hover:bg-white/[0.05]"
              )
            ]}
          >
            <.icon
              name={icon}
              class={"w-4 h-4 flex-shrink-0 #{if @menu_value == value, do: "text-ink", else: "text-gray-500"}"}
            />
            <span class="flex-1 font-display font-bold uppercase tracking-wide">{label}</span>
            <.icon :if={@menu_value == value} name="lucide-check" class="w-3.5 h-3.5 text-ink" />
          </button>
        </div>
      </.specimen>

      <.specimen title="Panels" note="indicia/1, .ink-rail">
        <div class="w-full max-w-2xl">
          <.indicia>
            <:item label="Pages">1,284</:item>
            <:item label="Size">2.1 GB</:item>
            <:item label="Age rating">Teen</:item>
          </.indicia>
        </div>
        <div class="ink-rail flex rounded-lg w-64">
          <div class="flex-1 bg-gray-900 rounded-lg ring-1 ring-white/10 px-5 py-4">
            <h3 class="font-display font-black uppercase text-2xl leading-none text-white">
              Filters <span class="text-ink tabular-nums">2</span>
            </h3>
            <p class="mt-2.5 text-[11px] font-bold tracking-[0.16em] uppercase text-gray-300">Section label</p>
          </div>
        </div>
      </.specimen>

      <.specimen title="Cover" note="hero_cover/1, media_card/1">
        <div class="pb-4 pr-16">
          <.hero_cover id="ui-hero-cover" />
        </div>
        <.media_card navigate="/dev/ui" title="Media card" subtitle="2024" badge="#1" progress={0.4} class="w-36" />
        <.media_card navigate="/dev/ui#read" title="Read card" subtitle="2024" progress={1.0} class="w-36" />
      </.specimen>
    </.detail_page>
    """
  end
end
