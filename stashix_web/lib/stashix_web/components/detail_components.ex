defmodule StashixWeb.DetailComponents do
  @moduledoc "Shared hero pieces for the series and book detail pages."
  use Phoenix.Component

  alias Phoenix.LiveView.JS
  import StashixUi.Icon, only: [icon: 1]
  import StashixWeb.CoreComponents, only: [blurhash_image: 1]

  @doc """
  Full-bleed wrapper for a detail page: a blurred wash of the cover plus a
  halftone texture behind the content. Negative margins cancel the layout's
  page padding so the wash reaches the edges.
  """
  attr :cover_src, :string, default: nil
  slot :inner_block, required: true

  def detail_page(assigns) do
    ~H"""
    <div class="relative overflow-x-clip -mx-6 -mt-6 px-6 pt-6 xl:-mx-12 xl:px-12 2xl:-mx-20 2xl:px-20">
      <div class="absolute inset-x-0 top-0 h-[34rem] overflow-hidden pointer-events-none" aria-hidden="true">
        <div :if={@cover_src} class="detail-backdrop absolute inset-0">
          <img src={@cover_src} alt="" class="w-full h-full object-cover" />
        </div>
        <div class="halftone absolute inset-0"></div>
      </div>
      <div class="relative max-w-5xl mx-auto space-y-8">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc "Back button + breadcrumb trail, with an optional right-aligned actions slot."
  attr :crumbs, :list, required: true, doc: "[{label, path | nil}] — the last entry is the current page"
  slot :actions

  def detail_crumbs(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-x-3 gap-y-3 text-xs">
      <button
        onclick="history.back()"
        class="flex items-center justify-center w-8 h-8 rounded-full bg-white/5 hover:bg-white/15 text-gray-300 hover:text-white backdrop-blur-sm transition-colors flex-shrink-0"
        aria-label="Back"
      >
        <.icon name="lucide-arrow-left" class="w-4 h-4" />
      </button>
      <nav class="flex items-center gap-2 flex-1 min-w-0 overflow-hidden font-medium uppercase tracking-[0.12em]">
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
  Hero cover with a zoom lightbox. `stack` is a list of extra cover URLs fanned
  out behind the main cover (used for series).
  """
  attr :id, :string, required: true
  attr :src, :string, default: nil
  attr :full_src, :string, default: nil
  attr :alt, :string, default: ""
  attr :blurhash, :string, default: nil
  attr :stack, :list, default: []

  def hero_cover(assigns) do
    ~H"""
    <div class="cover-stack relative w-44 sm:w-52 md:w-60 aspect-[2/3] flex-shrink-0">
      <div
        :for={{url, depth} <- @stack |> Enum.with_index(1) |> Enum.reverse()}
        class="cover-stack-card absolute inset-0 rounded-md overflow-hidden bg-gray-800 ring-1 ring-white/10 shadow-2xl"
        data-depth={depth}
        aria-hidden="true"
      >
        <img
          src={url}
          alt=""
          loading="lazy"
          class="w-full h-full object-cover opacity-60"
          onerror="this.style.display='none'"
        />
      </div>
      <div class="cover-stack-top group absolute inset-0 rounded-md overflow-hidden ring-1 ring-white/15 shadow-[0_24px_60px_-12px_rgba(0,0,0,0.9)]">
        <%= if @src do %>
          <.blurhash_image id={@id} src={@src} alt={@alt} blurhash={@blurhash} />
          <button
            phx-click={JS.show(to: "##{@id}-lightbox")}
            class="absolute inset-0 flex items-center justify-center bg-black/0 hover:bg-black/30 transition-colors cursor-zoom-in"
            aria-label="View cover full screen"
          >
            <.icon
              name="lucide-zoom-in"
              class="w-8 h-8 text-white opacity-0 group-hover:opacity-100 transition-opacity drop-shadow-lg"
            />
          </button>
        <% else %>
          <div class="w-full h-full flex items-center justify-center bg-gray-800 text-gray-600">
            <.icon name="lucide-layers" class="w-14 h-14" />
          </div>
        <% end %>
      </div>
    </div>

    <div :if={@src} id={"#{@id}-lightbox"} style="display:none" class="fixed inset-0 z-50">
      <div phx-click={JS.hide(to: "##{@id}-lightbox")} class="absolute inset-0 bg-black/90 cursor-zoom-out"></div>
      <div class="absolute inset-0 flex items-center justify-center" style="pointer-events:none">
        <img
          src={@full_src || @src}
          alt={@alt}
          loading="lazy"
          class="max-h-[90vh] max-w-[90vw] object-contain rounded-lg shadow-2xl cursor-default"
          style="pointer-events:auto"
          onclick="event.stopPropagation()"
        />
      </div>
      <button
        phx-click={JS.hide(to: "##{@id}-lightbox")}
        class="absolute top-4 right-4 w-9 h-9 flex items-center justify-center rounded-full bg-black/70 text-white hover:bg-black/90 transition-colors"
        aria-label="Close"
      >
        <.icon name="lucide-x" class="w-5 h-5" />
      </button>
    </div>
    """
  end

  @doc "Fine-print row of facts, like the indicia at the foot of a comic's first page."
  slot :item do
    attr :label, :string, required: true
    attr :show, :boolean
  end

  def indicia(assigns) do
    assigns = assign(assigns, item: Enum.filter(assigns.item, &Map.get(&1, :show, true)))

    ~H"""
    <dl :if={@item != []} class="flex flex-wrap gap-x-10 gap-y-4 border-y border-white/10 py-4">
      <div :for={item <- @item} class="min-w-0">
        <dt class="text-[10px] font-semibold tracking-[0.16em] uppercase text-gray-500 mb-1">{item.label}</dt>
        <dd class="text-sm text-gray-200 tabular-nums">{render_slot(item)}</dd>
      </div>
    </dl>
    """
  end
end
