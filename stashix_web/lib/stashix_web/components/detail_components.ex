defmodule StashixWeb.DetailComponents do
  @moduledoc "Shared hero pieces for the series and book detail pages."
  use Phoenix.Component

  alias Phoenix.LiveView.JS
  import StashixWeb.UI.Icon, only: [icon: 1]
  import StashixWeb.CoreComponents, only: [blurhash_image: 1]
  import StashixWeb.UI.Ink, only: [panel: 1, stat_list: 1, stat: 1]

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
    <div class="cover-stack rise relative w-44 sm:w-52 md:w-60 aspect-[2/3] flex-shrink-0">
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
    <.panel :if={@item != []} variant="indicia">
      <.stat_list class="px-6 py-5">
        <.stat :for={item <- @item} label={item.label}>{render_slot(item)}</.stat>
      </.stat_list>
    </.panel>
    """
  end
end
