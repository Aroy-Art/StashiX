defmodule StashixWeb.AuthComponents do
  @moduledoc """
  The signed-out pages (login, first-run setup), laid out like the cover of a
  comic: masthead across the top, issue box in the corner, the form where the
  cover art would be, a barcode strip along the foot.
  """
  use Phoenix.Component

  import StashixWeb.UI.Ink, only: [eyebrow: 1, display_heading: 1]

  @version Mix.Project.config()[:version]

  @doc """
  `issue` goes in the corner box above the app version; `heading` titles the
  form panel; `:steps` is an optional row above the panel.
  """
  attr :issue, :string, default: "#1"
  attr :tagline, :string, default: "Your long box, online"
  attr :heading, :string, required: true
  slot :steps
  slot :inner_block, required: true

  def cover_page(assigns) do
    assigns = assign(assigns, version: @version)

    ~H"""
    <div class="relative min-h-dvh flex items-center justify-center px-4 py-8 sm:py-12 bg-gray-950 text-gray-100 overflow-hidden">
      <div class="cover-wash absolute inset-0 pointer-events-none" aria-hidden="true"></div>

      <main class="cover-page relative w-full max-w-lg">
        <div class="halftone absolute inset-0" aria-hidden="true"></div>

        <header class="relative flex items-stretch gap-3 sm:gap-4 p-4 sm:p-5 pb-3">
          <div class="cover-issue-box flex-shrink-0 flex flex-col items-center justify-center px-2.5 py-1.5 bg-ink text-zinc-950 text-center">
            <span class="font-display font-black text-3xl leading-none">{@issue}</span>
            <span class="mt-1 pt-1 border-t-2 border-zinc-950 text-[10px] font-bold tracking-[0.12em] tabular-nums">
              v{@version}
            </span>
          </div>
          <div class="min-w-0 flex-1">
            <p class="cover-masthead font-display font-black uppercase leading-[0.8] text-white">
              Stash<span class="text-violet-400">iX</span>
            </p>
            <div class="mt-2 h-1.5 bg-gradient-to-r from-violet-500 via-ink to-ink"></div>
            <.eyebrow tone="light" class="mt-2 truncate">{@tagline}</.eyebrow>
          </div>
        </header>

        <div class="relative px-4 sm:px-8 pt-3 pb-6 sm:pb-8">
          <div :if={@steps != []} class="flex items-center gap-2 mb-4">{render_slot(@steps)}</div>
          <section class="cover-panel relative bg-gray-900 px-5 sm:px-6 py-5 sm:py-6">
            <.display_heading level={1} size="section" class="mb-5">{@heading}</.display_heading>
            {render_slot(@inner_block)}
          </section>
        </div>

        <footer class="relative flex items-end justify-between gap-4 px-4 sm:px-5 pb-4">
          <div class="cover-barcode h-9 w-32" aria-hidden="true"></div>
          <.eyebrow size="sm" tone="muted" class="text-right">Self-hosted · read anywhere</.eyebrow>
        </footer>
      </main>
    </div>
    """
  end

  @doc "One numbered step above the cover panel; the current one is an ink sticker."
  attr :number, :integer, required: true
  attr :current, :boolean, default: false
  attr :done, :boolean, default: false
  slot :inner_block, required: true

  def cover_step(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 px-2 pt-0.5 rounded-sm font-display font-black uppercase text-lg leading-tight",
      cond do
        @current -> "bg-ink text-zinc-950 -rotate-1"
        @done -> "bg-white/10 text-gray-200"
        true -> "text-gray-400 ring-1 ring-white/15"
      end
    ]}>
      <span class="tabular-nums">{@number}</span>
      {render_slot(@inner_block)}
    </span>
    """
  end
end
