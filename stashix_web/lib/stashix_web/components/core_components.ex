# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.CoreComponents do
  @moduledoc """
  App-level components built from the `StashixWeb.UI` primitives: flash
  messages, the confirm dialog, cover cards and rows for books and series,
  the browse toolbar, pagination and the library menu.

  Primitives (buttons, fields, menus, dialogs, page furniture) live under
  `lib/stashix_web/components/ui/`.
  """
  use Phoenix.Component
  use Gettext, backend: StashixWeb.Gettext

  import StashixWeb.UI.Icon
  import StashixWeb.UI.Dialog, only: [dialog: 1, dialog_footer: 1]
  import StashixWeb.UI.Ink, only: [eyebrow: 1, ink_button: 1, pill: 1, sticker: 1, progress_bar: 1]
  import StashixWeb.UI.Menu, only: [ink_menu: 1, ink_select: 1, menu_item: 1, menu_separator: 1]

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :auto_dismiss, :boolean, default: false, doc: "clear itself after a few seconds"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      phx-mounted={@auto_dismiss && JS.dispatch("stashix:flash-shown")}
      role="alert"
      class={[
        "flash-caption relative w-80 sm:w-96 max-w-full pl-4 pr-10 py-3 cursor-pointer pointer-events-auto",
        @kind == :info && "flash-caption-info bg-ink text-zinc-950",
        @kind == :error && "flash-caption-error bg-red-600 text-white"
      ]}
      {@rest}
    >
      <p :if={@title} class="font-display font-black uppercase text-xl leading-none tracking-wide">{@title}</p>
      <p class="mt-1 text-sm font-semibold leading-5">{msg}</p>
      <button
        type="button"
        class="absolute top-1.5 right-1.5 p-1.5 rounded-sm opacity-60 hover:opacity-100 hover:bg-black/15 transition"
        aria-label={gettext("close")}
      >
        <.icon name="lucide-x" class="h-4 w-4" />
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} class="fixed bottom-5 right-5 left-5 sm:left-auto z-50 flex flex-col items-end gap-5 pointer-events-none">
      <.flash kind={:info} title={gettext("Success!")} flash={@flash} auto_dismiss />
      <.flash kind={:error} title={gettext("Error!")} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error")}
        phx-connected={hide("#client-error")}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="lucide-loader-circle" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error")}
        phx-connected={hide("#server-error")}
        hidden
      >
        {gettext("Hang in there while we get back on track")}
        <.icon name="lucide-loader-circle" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders a dark-themed confirmation dialog driven by server state.

  Pass a `confirm` map with keys `:title`, `:message`, `:event`, and optionally
  `:params` (map of extra phx-value bindings). When non-nil the dialog is shown.
  The host LiveView must handle `"confirm_action"` and `"cancel_confirm"` events.

  ## Example

      <.confirm_dialog confirm={@pending_confirm} />
  """
  attr :confirm, :map, default: nil

  def confirm_dialog(assigns) do
    ~H"""
    <.dialog
      :if={@confirm}
      id="confirm-dialog"
      size="sm"
      title={@confirm.title}
      on_close={JS.push("cancel_confirm")}
    >
      <p class="text-sm text-fg-soft">{@confirm.message}</p>
      <.dialog_footer>
        <.ink_button type="button" variant="ghost" size="md" phx-click="cancel_confirm">Cancel</.ink_button>
        <.ink_button type="button" variant="danger" size="md" phx-click="confirm_action">
          {@confirm[:confirm_label] || "Confirm"}
        </.ink_button>
      </.dialog_footer>
    </.dialog>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all transform ease-out duration-300", "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  attr :id, :string, required: true
  attr :src, :string, required: true
  attr :alt, :string, default: ""
  attr :blurhash, :string, default: nil
  attr :class, :string, default: "w-full h-full object-cover block"
  attr :onerror, :string, default: nil

  def blurhash_image(assigns) do
    ~H"""
    <canvas
      :if={@blurhash}
      id={"bh-#{@id}"}
      width="32"
      height="48"
      class="absolute inset-0 w-full h-full"
      style="filter:blur(6px);transform:scale(1.05)"
    ></canvas>
    <img
      id={@id}
      phx-hook="CoverImage"
      src={@src}
      alt={@alt}
      class={@class}
      data-blurhash={@blurhash}
      data-canvas-id={"bh-#{@id}"}
      onerror={@onerror}
    />
    """
  end

  @doc """
  Cover card for a book or a series: the cover with its marks, title and
  subtitle underneath.

    * `badge` — ink sticker in the bottom-left corner (issue number, issue count)
    * `page_count` — small page tally in the bottom-right corner (books only)
    * `progress` — fraction read; draws a bar along the bottom edge and, at 1.0,
      the read mark
    * `read_mark` — `check` (a round green tick) or `stamp` (a tilted READ
      stamp). Leave it out and the card follows the signed-in user's setting,
      which the layout publishes as `data-read-mark` (see ink.css).
    * `type` — `:book` or `:series`, picks the placeholder icon
    * `stack` — more covers of the same series; they slide out from behind on
      hover and are only fetched then
  """
  attr :navigate, :any, required: true
  attr :title, :string, required: true
  attr :cover_url, :string, default: nil
  attr :size, :string, default: nil
  attr :subtitle, :string, default: nil
  attr :badge, :string, default: nil
  attr :progress, :float, default: nil
  attr :read_mark, :string, default: nil, values: [nil, "check", "stamp"]
  attr :type, :atom, default: :book
  attr :page_count, :integer, default: nil
  attr :blurhash, :string, default: nil
  attr :stack, :list, default: [], doc: "up to two more cover URLs, fanned out behind the cover on hover"

  attr :scope, :string,
    default: nil,
    doc: "set when the same item can appear twice on a page, to keep element ids unique"

  attr :class, :string, default: ""

  def media_card(assigns) do
    assigns =
      assigns
      |> assign(
        :img_src,
        if(assigns.cover_url && assigns.size,
          do: "#{assigns.cover_url}?s=#{assigns.size}",
          else: assigns.cover_url
        )
      )
      |> assign(:cover_id, "cover-#{:erlang.phash2({assigns.scope, assigns.navigate})}")
      |> assign(:read, is_number(assigns.progress) and assigns.progress >= 1.0)
      |> assign(:fallback_icon, if(assigns.type == :series, do: "lucide-book-copy", else: "lucide-book-open"))

    ~H"""
    <.link navigate={@navigate} data-read-mark={@read_mark} class={["media-card group relative block min-w-0", @class]}>
      <div class="relative">
        <span
          :for={{url, depth} <- @stack |> Enum.take(2) |> Enum.with_index(1) |> Enum.reverse()}
          class="media-card-fan"
          data-depth={depth}
          style={"--src: url('#{url}')"}
          aria-hidden="true"
        ></span>
        <div class="media-card-cover relative aspect-[2/3] rounded-md overflow-hidden bg-raised ring-1 ring-edge">
          <%= if @img_src do %>
            <.blurhash_image
              id={@cover_id}
              src={@img_src}
              alt={@title}
              blurhash={@blurhash}
              class="w-full h-full object-cover"
              onerror="this.style.display='none';this.nextElementSibling?.style.setProperty('display','flex')"
            />
            <div class="w-full h-full hidden items-center justify-center text-muted">
              <.icon name={@fallback_icon} class="w-8 h-8" />
            </div>
          <% else %>
            <div class="w-full h-full flex items-center justify-center text-muted">
              <.icon name={@fallback_icon} class="w-8 h-8" />
            </div>
          <% end %>

          <div
            :if={@read}
            class="read-mark-stamp absolute inset-0 bg-canvas/45 pointer-events-none"
            aria-hidden="true"
          >
          </div>
          <div class="absolute inset-x-0 bottom-0 h-14 bg-gradient-to-t from-gray-950/85 to-transparent pointer-events-none">
          </div>

          <.sticker :if={@badge} size="xs" tilt={false} class="absolute bottom-2 left-2 max-w-[calc(100%-1rem)] truncate">
            {@badge}
          </.sticker>
          <span
            :if={@type == :book && @page_count && @page_count > 0}
            class={[
              "absolute right-2 flex items-center gap-0.5 px-1 rounded-sm bg-canvas/70 text-[10px] font-semibold text-fg-soft tabular-nums",
              if(@badge, do: "top-2", else: "bottom-2")
            ]}
            title={"#{@page_count} pages"}
          >
            <.icon name="lucide-sticky-note" class="w-2.5 h-2.5 shrink-0" />
            {@page_count}
          </span>

          <span
            :if={@read}
            class="read-mark-check absolute top-2 left-2 flex items-center justify-center w-6 h-6 rounded-full bg-green-500 text-white ring-2 ring-canvas/70 shadow-[0_2px_6px_rgb(0_0_0/0.6)]"
            title="Read"
          >
            <.icon name="lucide-check" class="w-3.5 h-3.5 stroke-[3]" />
            <span class="sr-only">Read</span>
          </span>
          <span
            :if={@read}
            class="read-mark-stamp read-stamp absolute top-[14%] left-1/2 px-2 pt-0.5 border-[3px] border-ink rounded-sm bg-canvas/60 text-ink font-display font-black uppercase text-xl leading-none"
          >
            Read
          </span>

          <.progress_bar
            :if={@progress}
            value={@progress}
            rounded={false}
            track="bg-canvas/70"
            class="absolute bottom-0 inset-x-0 h-1"
          />
        </div>
      </div>
      <div class="pt-2 px-0.5">
        <p class="text-[13px] leading-snug font-semibold text-fg-soft group-hover:text-fg transition-colors line-clamp-2">
          {@title}
        </p>
        <p :if={@subtitle} class="mt-0.5 text-xs text-muted tabular-nums">{@subtitle}</p>
      </div>
    </.link>
    """
  end

  @doc "`media_card/1` for a series: years, issue count and the fanned stack of its next covers."
  attr :series, :map, required: true
  attr :size, :string, default: "m"
  attr :scope, :string, default: nil
  attr :subtitle, :string, default: nil, doc: "replaces the years"
  attr :badge, :string, default: nil, doc: "replaces the issue count"
  attr :class, :string, default: ""

  def series_card(assigns) do
    ~H"""
    <.media_card
      navigate={"/series/#{@series.id}"}
      title={@series.name}
      cover_url={"/api/series/#{@series.id}/cover"}
      size={@size}
      subtitle={@subtitle || Stashix.Formatters.series_years(@series)}
      badge={
        @badge ||
          (@series.issue_count && "#{@series.issue_count} #{if @series.issue_count == 1, do: "issue", else: "issues"}")
      }
      type={:series}
      blurhash={@series.cover_blurhash}
      stack={Enum.map(Map.get(@series, :stack_book_ids) || [], &"/api/books/#{&1}/cover?s=s")}
      scope={@scope}
      class={@class}
    />
    """
  end

  @doc """
  `media_card/1` for a book. `as={:issue}` puts the issue number in the title
  and on a sticker and names the series underneath; the default shows the
  year and the page count. `read` is the number of pages read so far.
  """
  attr :book, :map, required: true
  attr :as, :atom, default: :book, values: [:book, :issue]
  attr :read, :integer, default: nil
  attr :size, :string, default: "m"
  attr :scope, :string, default: nil
  attr :subtitle, :string, default: nil, doc: "replaces the series name or year"
  attr :class, :string, default: ""

  def book_card(assigns) do
    book = assigns.book
    issue? = assigns.as == :issue
    series = if issue? and Ecto.assoc_loaded?(book.series), do: book.series
    year = book.year && to_string(book.year)

    assigns =
      assign(assigns,
        title: if(issue? and book.issue_number, do: "##{book.issue_number} – #{book.title}", else: book.title),
        subtitle: assigns.subtitle || (series && series.name) || year,
        badge:
          cond do
            !issue? or is_nil(book.issue_number) -> nil
            book.volume && (book.series_volume_count || 2) > 1 -> "Vol #{book.volume} ##{book.issue_number}"
            true -> "##{book.issue_number}"
          end,
        progress:
          if(assigns.read && book.page_count && book.page_count > 1,
            do: assigns.read / (book.page_count - 1)
          ),
        blurhash: Ecto.assoc_loaded?(book.cover) && book.cover && book.cover.blurhash
      )

    ~H"""
    <.media_card
      navigate={"/book/#{@book.id}"}
      title={@title}
      cover_url={"/api/books/#{@book.id}/cover"}
      size={@size}
      subtitle={@subtitle}
      badge={@badge}
      progress={@progress}
      page_count={if @as == :book, do: @book.page_count}
      type={:book}
      blurhash={@blurhash || nil}
      scope={@scope}
      class={@class}
    />
    """
  end

  @doc """
  Compact row for a book or series in a list: small cover, a line naming what
  it belongs to, the title, then either a progress bar or a line of detail.
  Takes a fraction of the height of a `media_card/1`.
  """
  attr :navigate, :string, required: true
  attr :title, :string, required: true
  attr :cover_url, :string, required: true
  attr :eyebrow, :string, default: nil
  attr :detail, :string, default: nil
  attr :progress, :float, default: nil
  attr :class, :any, default: nil

  def media_row(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "group flex items-center gap-3 min-w-0 p-2.5 rounded-md bg-fg/[0.03] ring-1 ring-edge hover:bg-fg/[0.07] hover:ring-ink/60 transition-colors",
        @class
      ]}
    >
      <div class="w-12 aspect-[2/3] flex-shrink-0 rounded-sm overflow-hidden bg-raised">
        <img
          src={"#{@cover_url}?s=s"}
          alt=""
          loading="lazy"
          class="w-full h-full object-cover"
          onerror="this.style.display='none'"
        />
      </div>
      <div class="flex-1 min-w-0">
        <.eyebrow :if={@eyebrow} size="sm" class="truncate mb-0.5">{@eyebrow}</.eyebrow>
        <p class="text-sm font-semibold leading-snug text-fg group-hover:text-fg line-clamp-2">{@title}</p>
        <div :if={@progress} class="flex items-center gap-2 mt-1.5">
          <.progress_bar value={@progress} class="flex-1 h-1" />
          <span class="text-[10px] font-semibold text-muted tabular-nums">{round(min(@progress, 1.0) * 100)}%</span>
        </div>
        <p :if={!@progress && @detail} class="mt-0.5 text-xs text-muted tabular-nums">{@detail}</p>
      </div>
    </.link>
    """
  end

  @doc "`media_row/1` for a book; `read` is the number of pages read so far."
  attr :book, :map, required: true
  attr :read, :integer, default: nil
  attr :class, :any, default: nil

  def book_row(assigns) do
    book = assigns.book
    series = if Ecto.assoc_loaded?(book.series), do: book.series

    assigns =
      assign(assigns,
        title: if(book.issue_number, do: "##{book.issue_number} – #{book.title}", else: book.title),
        eyebrow: series && series.name,
        detail:
          [book.year, book.page_count && book.page_count > 0 && "#{book.page_count} pages"]
          |> Enum.filter(& &1)
          |> Enum.join(" · "),
        progress:
          if(assigns.read && book.page_count && book.page_count > 1,
            do: min(assigns.read / (book.page_count - 1), 1.0)
          )
      )

    ~H"""
    <.media_row
      navigate={"/book/#{@book.id}"}
      title={@title}
      cover_url={"/api/books/#{@book.id}/cover"}
      eyebrow={@eyebrow}
      detail={@detail}
      progress={@progress}
      class={@class}
    />
    """
  end

  @doc "Admin ⋮ menu for a library: scan, force rescan, settings. Events are handled by `StashixWeb.Live.Hooks`."
  attr :id, :string, required: true
  attr :library_id, :string, required: true
  attr :class, :any, default: nil

  def library_menu(assigns) do
    ~H"""
    <.ink_menu id={@id} class={@class}>
      <:trigger
        label="Library actions"
        class="p-1 text-fg/30 hover:text-ink transition-colors"
      >
        <.icon name="lucide-ellipsis-vertical" class="w-3.5 h-3.5" />
      </:trigger>
      <.menu_item icon="lucide-refresh-cw" phx-click={JS.push("sidebar_scan", value: %{id: @library_id})}>
        Scan for new files
      </.menu_item>
      <.menu_item icon="lucide-rotate-ccw" phx-click={JS.push("sidebar_force_scan", value: %{id: @library_id})}>
        Force rescan
      </.menu_item>
      <.menu_separator />
      <.menu_item icon="lucide-settings" navigate="/admin/libraries">Settings</.menu_item>
    </.ink_menu>
    """
  end

  # ---------------------------------------------------------------------------
  # Browse / list-page shared components
  # ---------------------------------------------------------------------------

  @doc """
  Control row above a browse grid: library filter pills on the left (only
  with more than one library to pick from), sort on the right.
  """
  attr :libraries, :list, default: []
  attr :library_id, :string, default: nil
  attr :sort_options, :list, required: true
  attr :sort, :string, required: true

  def browse_toolbar(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-between gap-x-4 gap-y-3 pb-4 border-b border-fg/15">
      <div class="flex flex-wrap items-center gap-1.5">
        <.library_filter :if={length(@libraries) > 1} libraries={@libraries} selected_id={@library_id} />
      </div>
      <.sort_select options={@sort_options} selected={@sort} class="ml-auto" />
    </div>
    """
  end

  attr :libraries, :list, required: true
  attr :selected_id, :string, default: nil
  attr :event, :string, default: "filter_library"

  def library_filter(assigns) do
    ~H"""
    <.pill tag="button" type="button" active={is_nil(@selected_id)} phx-click={@event} phx-value-id="">
      All libraries
    </.pill>
    <.pill
      :for={lib <- @libraries}
      tag="button"
      type="button"
      active={@selected_id == lib.id}
      phx-click={@event}
      phx-value-id={lib.id}
    >
      {lib.name}
    </.pill>
    """
  end

  attr :id, :string, default: "sort-select"
  attr :options, :list, required: true
  attr :selected, :string, required: true
  attr :event, :string, default: "sort"
  attr :class, :string, default: nil

  def sort_select(assigns) do
    ~H"""
    <form id={@id} phx-change={@event} class={@class}>
      <.ink_select id={"#{@id}-input"} name="value" label="Sort" value={@selected} options={@options} />
    </form>
    """
  end

  # ---------------------------------------------------------------------------

  attr :id, :string, default: nil
  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :on_page, :string, default: "goto_page"
  attr :scroll_to, :string, default: nil

  def pagination(assigns) do
    assigns = assign(assigns, :pages, pagination_pages(assigns.page, assigns.total_pages))

    ~H"""
    <nav :if={@total_pages > 1} id={@id} aria-label="Pages" class="flex items-center justify-center gap-1">
      <.page_step
        icon="lucide-chevron-first"
        label="First page"
        disabled={@page == 1}
        click={page_click(@on_page, 1, @scroll_to)}
      />
      <.page_step
        icon="lucide-chevron-left"
        label="Previous page"
        disabled={@page == 1}
        click={page_click(@on_page, @page - 1, @scroll_to)}
      />

      <button
        :for={{p, i} <- Enum.with_index(@pages, 1)}
        type="button"
        phx-click={page_click(@on_page, p, @scroll_to)}
        aria-label={"Page #{p}"}
        aria-current={p == @page && "page"}
        class={[
          "h-9 min-w-9 px-1.5 items-center justify-center rounded-sm font-display font-black text-xl leading-none tabular-nums transition-colors",
          if(i > 5 and p != @page, do: "hidden sm:flex", else: "flex"),
          if(p == @page,
            do: "sticker bg-ink text-zinc-950",
            else: "text-muted hover:text-fg hover:bg-fg/10"
          )
        ]}
      >
        {p}
      </button>

      <.page_step
        icon="lucide-chevron-right"
        label="Next page"
        disabled={@page == @total_pages}
        click={page_click(@on_page, @page + 1, @scroll_to)}
      />
      <.page_step
        icon="lucide-chevron-last"
        label="Last page"
        disabled={@page == @total_pages}
        click={page_click(@on_page, @total_pages, @scroll_to)}
      />
    </nav>
    """
  end

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :disabled, :boolean, required: true
  attr :click, JS, required: true

  defp page_step(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@click}
      disabled={@disabled}
      aria-label={@label}
      class="flex items-center justify-center w-9 h-9 rounded-sm text-muted hover:text-fg hover:bg-fg/10 disabled:opacity-25 disabled:pointer-events-none transition-colors"
    >
      <.icon name={@icon} class="w-4 h-4" />
    </button>
    """
  end

  defp page_click(event, page, nil), do: JS.push(event, value: %{"page" => to_string(page)})

  defp page_click(event, page, scroll_to) do
    JS.push(event, value: %{"page" => to_string(page)})
    |> JS.dispatch("stashix:scroll-to", detail: %{id: scroll_to})
  end

  defp pagination_pages(_current, total) when total <= 11, do: Enum.to_list(1..total)

  defp pagination_pages(current, total) do
    half = 5
    start = max(1, min(current - half, total - 10))
    finish = min(total, start + 10)
    Enum.to_list(start..finish)
  end
end
