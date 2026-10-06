defmodule StashixWeb.UI.Logo do
  @moduledoc "The StashiX wordmark."
  use Phoenix.Component

  @doc """
  "Stash" in white, "iX" in violet with an aqua dot on the i, and the trail
  sweeping off the X, set in the display face. It scales with the font size,
  so size it with a text class. `glow` is the soft violet halo on the "iX".

  The aqua dot is a second "i" laid over the first and clipped to its top,
  so it follows the typeface instead of being drawn by hand.

  `id` only has to differ when two logos share a page: the trail's gradient
  and filter are referenced by id.
  """
  attr :id, :string, default: "logo"
  attr :glow, :boolean, default: true
  attr :class, :any, default: nil

  def logo(assigns) do
    ~H"""
    <span class={["logo relative inline-block font-display font-black leading-none whitespace-nowrap", @class]}>
      <span class="text-white">Stash</span><span class={["text-violet-500", @glow && "logo-glow"]}><span class="logo-i">i<span
            class="logo-dot"
            aria-hidden="true"
          >i</span></span>X</span>
      <svg class="logo-tail" viewBox="0 0 50 18" fill="none" aria-hidden="true">
        <defs>
          <linearGradient id={"#{@id}-trail"} x1="0" y1="0" x2="50" y2="0" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stop-color="#a78bfa" stop-opacity="0.85" />
            <stop offset="60%" stop-color="#a78bfa" stop-opacity="0.3" />
            <stop offset="100%" stop-color="#a78bfa" stop-opacity="0" />
          </linearGradient>
          <filter id={"#{@id}-glow"} x="-30%" y="-150%" width="200%" height="400%">
            <feGaussianBlur stdDeviation="2.5" result="blur" />
            <feMerge><feMergeNode in="blur" /><feMergeNode in="SourceGraphic" /></feMerge>
          </filter>
        </defs>
        <path
          d="M1 13 C16 13, 36 11, 49 2"
          stroke={"url(##{@id}-trail)"}
          stroke-width="3"
          stroke-linecap="round"
          filter={"url(##{@id}-glow)"}
        />
        <path
          d="M1 13 C14 13, 30 11, 44 5"
          stroke={"url(##{@id}-trail)"}
          stroke-width="1.2"
          stroke-linecap="round"
          opacity="0.8"
        />
      </svg>
    </span>
    """
  end
end
