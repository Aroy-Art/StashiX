defmodule StashixWeb.UI.Page do
  @moduledoc """
  Page furniture of the "ink" design language: the full-bleed page shell,
  breadcrumbs, heroes, titled sections, cover grids and shelves.
  Specimens live at `/dev/ui`.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS
  import StashixWeb.UI.Icon, only: [icon: 1]
  import StashixWeb.UI.Ink

  @doc """
  Full-bleed page wrapper: a blurred wash of `cover_src` plus a halftone
  texture behind the content. Negative margins cancel the layout's page
  padding so the wash reaches the edges. `wide` drops the reading-width cap
  for pages that lay out their own columns.
  """
  attr :cover_src, :string, default: nil
  attr :wide, :boolean, default: false
  attr :fade, :boolean, default: false, doc: "cross-fade the wash when cover_src changes on a live page"
  slot :inner_block, required: true

  def page(assigns) do
    ~H"""
    <div class="relative overflow-x-clip -mx-6 -mt-6 px-6 pt-6 xl:-mx-12 xl:px-12 2xl:-mx-20 2xl:px-20">
      <div class="absolute inset-x-0 top-0 h-[34rem] overflow-hidden pointer-events-none" aria-hidden="true">
        <div
          :if={@fade}
          id="detail-backdrop"
          phx-hook="BackdropFade"
          phx-update="ignore"
          data-src={@cover_src}
          class="detail-backdrop absolute inset-0"
        >
        </div>
        <div :if={!@fade && @cover_src} class="detail-backdrop absolute inset-0">
          <img src={@cover_src} alt="" class="backdrop-static w-full h-full object-cover" />
        </div>
        <div class="halftone absolute inset-0"></div>
      </div>
      <div class={["relative space-y-8", !@wide && "max-w-5xl mx-auto"]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc "Back button + breadcrumb trail, with an optional right-aligned actions slot."
  attr :crumbs, :list, required: true, doc: "[{label, path | nil}] — the last entry is the current page"
  slot :actions

  def crumbs(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-x-3 gap-y-3 text-xs">
      <.icon_button icon="lucide-arrow-left" label="Back" phx-click={JS.dispatch("phx:history-back")} />
      <nav
        aria-label="Breadcrumb"
        class="flex items-center gap-2 flex-1 min-w-0 overflow-hidden font-medium uppercase tracking-[0.12em]"
      >
        <%= for {{label, path}, idx} <- Enum.with_index(@crumbs) do %>
          <span :if={idx > 0} class="text-white/20 flex-shrink-0">/</span>
          <.link :if={path} navigate={path} class="text-gray-400 hover:text-white transition-colors flex-shrink-0">
            {label}
          </.link>
          <span :if={!path} class="text-gray-200 truncate min-w-0">{label}</span>
        <% end %>
      </nav>
      <div :if={@actions != []} class="ml-auto">{render_slot(@actions)}</div>
    </div>
    """
  end

  @doc """
  Text-only hero for pages without a cover: eyebrow, display title, and an
  optional ghost figure (`count`) looming behind it. `:meta` is the line of
  facts under the title, `:actions` the row of controls below that.
  """
  attr :title, :string, required: true
  attr :eyebrow, :string, default: nil
  attr :count, :any, default: nil
  attr :class, :any, default: nil
  slot :meta
  slot :actions

  def page_hero(assigns) do
    ~H"""
    <header class={["relative pt-2", @class]}>
      <.ghost_numeral :if={@count} class="hidden sm:block absolute -top-2 right-0 text-[7rem] xl:text-[9rem]">
        {@count}
      </.ghost_numeral>
      <.eyebrow :if={@eyebrow} class="rise relative mb-3" style="--i:1">{@eyebrow}</.eyebrow>
      <.display_heading level={1} size="hero" class="rise relative" style="--i:2">{@title}</.display_heading>
      <div
        :if={@meta != []}
        class="rise relative flex items-center flex-wrap gap-x-3 gap-y-1 mt-4 text-sm text-gray-300 tabular-nums"
        style="--i:3"
      >
        {render_slot(@meta)}
      </div>
      <div :if={@actions != []} class="rise relative flex flex-wrap items-center gap-2 mt-6" style="--i:4">
        {render_slot(@actions)}
      </div>
    </header>
    """
  end

  @doc "Block of content under a display heading, with optional `count` and right-aligned `:actions`."
  attr :title, :string, required: true
  attr :count, :any, default: nil
  attr :class, :any, default: nil
  attr :rest, :global
  slot :actions
  slot :inner_block, required: true

  def section(assigns) do
    ~H"""
    <section class={@class} {@rest}>
      <.section_header title={@title} count={@count} actions={@actions} />
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :title, :string, required: true
  attr :count, :any, default: nil
  attr :actions, :list, default: []

  defp section_header(assigns) do
    ~H"""
    <div class="flex items-end justify-between gap-4 mb-4">
      <.display_heading count={@count}>{@title}</.display_heading>
      <div :if={@actions != []} class="flex items-center gap-3 flex-shrink-0">{render_slot(@actions)}</div>
    </div>
    """
  end

  @doc """
  Responsive grid of covers. `wide` fills a full-width page (up to 8 columns);
  `narrow` is for pages capped at reading width (up to 6).
  """
  attr :id, :string, default: nil
  attr :cols, :string, default: "wide", values: ~w(wide narrow)
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def cover_grid(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "grid scroll-mt-4",
        if(@cols == "wide",
          do: "grid-cols-3 sm:grid-cols-4 md:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-8 gap-3 sm:gap-4",
          else: "grid-cols-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 gap-4"
        ),
        @class
      ]}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Titled, horizontally scrolling row of covers. Arrow buttons appear when the
  row overflows (and the screen is wide enough to want them). Children need a
  fixed width and `flex-shrink-0`.
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :count, :any, default: nil
  attr :class, :any, default: nil
  slot :actions
  slot :inner_block, required: true

  def shelf(assigns) do
    ~H"""
    <section id={"#{@id}-shelf"} phx-hook="Shelf" class={@class}>
      <div class="flex items-end justify-between gap-4 mb-4">
        <.display_heading count={@count}>{@title}</.display_heading>
        <div class="flex items-center gap-3 flex-shrink-0">
          {render_slot(@actions)}
          <div class="shelf-arrows items-center gap-1.5">
            <.icon_button
              icon="lucide-chevron-left"
              label={"Scroll #{@title} back"}
              phx-click={JS.dispatch("stashix:scroll-by", to: "##{@id}", detail: %{pages: -1})}
            />
            <.icon_button
              icon="lucide-chevron-right"
              label={"Scroll #{@title} forward"}
              phx-click={JS.dispatch("stashix:scroll-by", to: "##{@id}", detail: %{pages: 1})}
            />
          </div>
        </div>
      </div>
      <div id={@id} data-shelf-row class="flex gap-4 overflow-x-auto pb-2 scrollbar-hide">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  @doc """
  Placeholder for a list with nothing in it. `ghost` puts an outlined figure
  or word behind the title; without one, `icon` sits above it.
  """
  attr :title, :string, required: true
  attr :ghost, :string, default: nil
  attr :icon, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block
  slot :actions

  def empty_state(assigns) do
    ~H"""
    <div class={["relative flex flex-col items-center text-center py-10 sm:py-14", @class]}>
      <.ghost_numeral :if={@ghost} class="text-[10rem] sm:text-[13rem]">{@ghost}</.ghost_numeral>
      <.icon :if={!@ghost && @icon} name={@icon} class="w-12 h-12 mb-4 text-gray-700" />
      <h2 class={[
        "font-display font-black uppercase text-4xl sm:text-5xl leading-[0.9] text-white text-balance",
        @ghost && "-mt-9 sm:-mt-12"
      ]}>
        {@title}
      </h2>
      <p :if={@inner_block != []} class="mt-3 max-w-sm text-sm text-gray-300">{render_slot(@inner_block)}</p>
      <div :if={@actions != []} class="mt-7">{render_slot(@actions)}</div>
    </div>
    """
  end
end
