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
    <.page wide>
      <.crumbs crumbs={[{"Home", "/"}, {"Dev", nil}, {"Style guide", nil}]}>
        <:actions><.kbd keys={["Ctrl", "K"]} /></:actions>
      </.crumbs>

      <.page_hero title="Style guide" eyebrow="Dev only" count="UI">
        <:meta>
          <span>Every shared component, every variant</span>
          <span class="text-violet-300">docs/ui-redesign-plan.md</span>
        </:meta>
      </.page_hero>

      <.specimen title="Colour">
        <div :for={{name, class, note} <- @colors} class="w-40">
          <div class={["h-14 rounded-md ring-1 ring-white/15", class]}></div>
          <.eyebrow size="sm" tone="ink" class="mt-2">{name}</.eyebrow>
          <p class="text-xs text-gray-400">{note}</p>
        </div>
      </.specimen>

      <.specimen title="Type" note="eyebrow, display_heading, text_link">
        <div class="space-y-3">
          <div class="flex flex-wrap items-baseline gap-6">
            <.eyebrow>Eyebrow md</.eyebrow>
            <.eyebrow tone="light">Light</.eyebrow>
            <.eyebrow size="sm" tone="ink">Small ink</.eyebrow>
            <.eyebrow size="sm" tone="muted">Small muted</.eyebrow>
            <.eyebrow size="xs" tone="muted">Extra small</.eyebrow>
          </div>
          <.display_heading size="hero">Hero headline</.display_heading>
          <.display_heading count={12}>Section heading</.display_heading>
          <.display_heading size="panel" level={3} count={2} count_tone="ink">Panel heading</.display_heading>
          <p class="text-[15px] text-gray-300 leading-7 max-w-xl">
            Body copy sits in the system sans at 15px on a relaxed leading, gray-300 on the page background.
          </p>
          <div class="flex items-center gap-6">
            <.text_link href="#">
              Text link <.icon name="lucide-arrow-right" class="w-4 h-4 text-ink" />
            </.text_link>
            <.text_link tone="subtle" href="#">
              <.icon name="lucide-rotate-ccw" class="w-4 h-4" /> Subtle link
            </.text_link>
          </div>
        </div>
      </.specimen>

      <.specimen title="Buttons" note="ink_button, split_button, icon_button">
        <.ink_button>
          <.icon name="lucide-play" class="w-4 h-4" /> Continue <span class="text-ink">#4</span>
        </.ink_button>
        <.ink_button variant="ghost"><.icon name="lucide-book-open" class="w-4 h-4" /> Ghost</.ink_button>
        <.ink_button variant="danger"><.icon name="lucide-trash-2" class="w-4 h-4" /> Danger</.ink_button>
        <.split_button>
          <.icon name="lucide-play" class="w-4 h-4" /> Read
          <:aside>
            <button class={split_aside_class()} aria-label="More">
              <.icon name="lucide-chevron-down" class="w-4 h-4" />
            </button>
          </:aside>
        </.split_button>
        <.icon_button icon="lucide-arrow-left" label="Icon button" />
      </.specimen>

      <.specimen title="Buttons, medium" note={~s(size="md")}>
        <.ink_button size="md">Save</.ink_button>
        <.ink_button size="md" variant="ghost">Cancel</.ink_button>
        <.ink_button size="md" variant="danger">Delete</.ink_button>
      </.specimen>

      <.specimen title="Stickers, pills, chips" note="sticker, kbd, pill, chip">
        <.sticker size="xs" tilt={false}>2</.sticker>
        <.sticker>#12</.sticker>
        <.sticker size="md">Up next</.sticker>
        <.sticker size="lg">#12</.sticker>
        <.kbd keys={["Ctrl", "K"]} />
        <.pill
          :for={value <- ~w(page width height)}
          tag="button"
          active={@segment == value}
          phx-click="set_segment"
          phx-value-value={value}
        >
          Fit {value}
        </.pill>
        <.chip navigate="/dev/ui" count={3}>Link chip</.chip>
        <.chip count={3}>Flat chip</.chip>
      </.specimen>

      <.specimen title="Segmented control" note=".ink-segmented — becomes <.segmented> in Phase 2">
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

      <.specimen title="Panels and figures" note="panel, stat_list, stat, progress_bar">
        <.panel variant="indicia" class="w-full max-w-2xl">
          <.stat_list class="px-6 py-5">
            <.stat label="Pages">1,284</.stat>
            <.stat label="Size">2.1 GB</.stat>
            <.stat label="Series" navigate="/series">42</.stat>
          </.stat_list>
        </.panel>
        <.panel variant="rail" class="w-64 rounded-lg">
          <div class="px-5 py-4 space-y-2.5">
            <.display_heading size="panel" level={3} count={2} count_tone="ink">Filters</.display_heading>
            <.eyebrow tone="light">Section label</.eyebrow>
          </div>
        </.panel>
        <.panel class="w-64 px-5 py-4 space-y-3">
          <.eyebrow size="sm" tone="muted">Plain panel</.eyebrow>
          <.progress_bar value={0.4} label="Reading progress" class="h-1.5" />
          <.progress_bar value={1.0} label="Finished" class="h-1.5" />
        </.panel>
      </.specimen>

      <.specimen title="Cover" note="hero_cover, media_card">
        <div class="pb-4 pr-16">
          <.hero_cover id="ui-hero-cover" />
        </div>
        <.media_card navigate="/dev/ui" title="Media card" subtitle="2024" badge="#1" progress={0.4} class="w-36" />
        <.media_card navigate="/dev/ui#read" title="Read card" subtitle="2024" progress={1.0} class="w-36" />
      </.specimen>

      <.section title="Section" count={6}>
        <:actions>
          <.text_link href="#">Show all <.icon name="lucide-arrow-right" class="w-4 h-4 text-ink" /></.text_link>
        </:actions>
        <.cover_grid>
          <.media_card :for={i <- 1..6} navigate={"/dev/ui#grid-#{i}"} title={"Grid card #{i}"} badge={"##{i}"} />
        </.cover_grid>
      </.section>

      <.shelf id="ui-shelf" title="Shelf" count={14}>
        <.media_card
          :for={i <- 1..14}
          navigate={"/dev/ui#shelf-#{i}"}
          title={"Shelf card #{i}"}
          class="flex-shrink-0 w-36"
        />
      </.shelf>

      <.specimen title="Empty states" note="empty_state">
        <.empty_state title="Nothing in the long box" ghost="0" class="flex-1">
          Loosen the filters or try another spelling.
          <:actions>
            <.ink_button><.icon name="lucide-filter-x" class="w-4 h-4" /> Clear filters</.ink_button>
          </:actions>
        </.empty_state>
        <.empty_state title="No series yet" icon="lucide-book-copy" class="flex-1" />
      </.specimen>
    </.page>
    """
  end
end
