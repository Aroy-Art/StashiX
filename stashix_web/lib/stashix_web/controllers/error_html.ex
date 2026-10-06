defmodule StashixWeb.ErrorHTML do
  @moduledoc """
  Error pages for HTML requests (see `render_errors` in config/config.exs).

  They render without a layout and must not be able to fail themselves, so the
  page is one self-contained document: no assigns from the request, no
  database, no icon files read from disk (the ghost is inline SVG). Only the
  stylesheet is shared with the app.
  """
  use StashixWeb, :html

  @copy %{
    "404" => {"This page isn't there", "Misfiled, or never printed."},
    "403" => {"Not in your box", "This one belongs to someone else's collection."},
    "401" => {"Sign in first", "The long box is locked."},
    "500" => {"A page tore", "That one is on us. Give it a moment and try again."},
    "503" => {"Back in a moment", "The shop is restocking the shelves."}
  }

  def render(template, _assigns) do
    status = template |> String.split(".") |> hd()

    {title, caption} =
      Map.get(@copy, status, {Phoenix.Controller.status_message_from_template(template), "Something went wrong."})

    error_page(%{status: status, title: title, caption: caption})
  end

  attr :status, :string, required: true
  attr :title, :string, required: true
  attr :caption, :string, required: true

  defp error_page(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="dark">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="theme-color" content="#030712" />
        <title>{@title} · Stashix</title>
        <link rel="icon" type="image/png" href={~p"/favicon.png"} />
        <link rel="stylesheet" href={~p"/assets/app.css"} />
      </head>
      <body class="bg-gray-950 text-gray-100 antialiased">
        <main class="reader-end relative min-h-dvh flex items-center justify-center px-6 py-16 overflow-hidden">
          <div class="halftone absolute inset-0" aria-hidden="true"></div>
          <span
            class="ghost-numeral pointer-events-none absolute -right-4 -bottom-10 text-[14rem] md:text-[24rem]"
            aria-hidden="true"
          >
            {@status}
          </span>

          <div class="relative flex flex-col sm:flex-row items-center gap-8 sm:gap-12 max-w-3xl">
            <%!-- The page that isn't there --%>
            <div
              class="reader-end-page reader-end-hollow relative flex items-center justify-center w-32 sm:w-48 flex-shrink-0 aspect-[2/3] rounded-sm"
              aria-hidden="true"
            >
              <svg
                class="reader-end-ghost w-14 h-14 sm:w-20 sm:h-20 text-ink"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <path d="M9 10h.01" /><path d="M15 10h.01" />
                <path d="M12 2a8 8 0 0 0-8 8v12l3-3 2.5 2.5L12 19l2.5 2.5L17 19l3 3V10a8 8 0 0 0-8-8z" />
              </svg>
            </div>

            <div class="min-w-0 text-center sm:text-left">
              <p class="flex items-center justify-center sm:justify-start gap-3">
                <span class="sticker inline-block px-2 pt-0.5 bg-ink text-zinc-950 font-display font-black text-2xl leading-none rounded-sm tabular-nums">
                  {@status}
                </span>
                <span class="text-[11px] font-bold tracking-[0.2em] uppercase text-violet-300">Error</span>
              </p>
              <h1 class="mt-3 font-display font-black uppercase text-5xl md:text-7xl leading-[0.88] text-white text-balance">
                {@title}
              </h1>
              <p class="reader-end-caption inline-block mt-5 px-3 py-1.5 bg-ink text-zinc-950 text-sm font-semibold">
                {@caption}
              </p>
              <div class="mt-8">
                <a
                  href={~p"/"}
                  class="ink-btn inline-flex items-center gap-2.5 px-6 py-2.5 bg-violet-600 hover:bg-violet-500 text-white font-display font-extrabold uppercase text-xl tracking-wide rounded-md"
                >
                  Back to the stash
                </a>
              </div>
            </div>
          </div>
        </main>
      </body>
    </html>
    """
  end
end
