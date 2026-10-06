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
    {:ok,
     assign(socket,
       page_title: "UI",
       colors: @colors,
       segment: "page",
       menu_value: "single",
       dialog: false,
       page: 3,
       select: %{"sort" => "title_asc", "publisher" => "", "role" => "user"}
     )}
  end

  @impl true
  def handle_event("set_segment", %{"v" => value}, socket), do: {:noreply, assign(socket, segment: value)}
  def handle_event("set_menu", %{"v" => value}, socket), do: {:noreply, assign(socket, menu_value: value)}
  def handle_event("noop", _params, socket), do: {:noreply, socket}

  def handle_event("flash", %{"kind" => "info"}, socket),
    do: {:noreply, put_flash(socket, :info, "Metadata updated for 12 issues.")}

  def handle_event("flash", %{"kind" => "error"}, socket),
    do: {:noreply, put_flash(socket, :error, "Could not reach the metadata source.")}

  def handle_event("set_page", %{"page" => page}, socket), do: {:noreply, assign(socket, page: String.to_integer(page))}
  def handle_event("toggle_dialog", _params, socket), do: {:noreply, assign(socket, dialog: !socket.assigns.dialog)}

  def handle_event("select_changed", params, socket),
    do: {:noreply, assign(socket, select: Map.take(params, ~w(sort publisher role)))}

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
          phx-value-v={value}
        >
          Fit {value}
        </.pill>
        <.chip navigate="/dev/ui" count={3}>Link chip</.chip>
        <.chip count={3}>Flat chip</.chip>
      </.specimen>

      <.specimen title="Segmented control" note="segmented, segment">
        <.segmented>
          <.segment
            :for={
              {value, icon} <- [
                {"page", "lucide-scan"},
                {"width", "lucide-move-horizontal"},
                {"height", "lucide-move-vertical"}
              ]
            }
            icon={icon}
            title={"Fit #{value}"}
            active={@segment == value}
            phx-click="set_segment"
            phx-value-v={value}
          />
        </.segmented>
        <.segmented vertical>
          <.segment icon="lucide-plus" title="Zoom in" />
          <.segment icon="lucide-minus" title="Zoom out" />
        </.segmented>
        <.segmented>
          <.segment class="gap-1 px-2.5 font-display font-bold tracking-wide text-sm">
            LTR <.icon name="lucide-arrow-right" class="w-3.5 h-3.5 text-ink" />
          </.segment>
        </.segmented>
      </.specimen>

      <.specimen title="Menu" note="ink_menu, menu_label, menu_item, menu_separator">
        <.ink_menu id="ui-menu-choice" align="start" panel_class="w-60">
          <:trigger class="ink-segmented h-8 items-center gap-1.5 px-2.5 text-gray-300 hover:text-white font-display font-bold uppercase tracking-wide text-sm">
            <.icon name="lucide-rectangle-vertical" class="w-4 h-4" /> View
            <.icon name="lucide-chevron-down" class="w-3 h-3" />
          </:trigger>
          <.menu_label>Layout</.menu_label>
          <.menu_item
            :for={
              {value, label, icon} <- [
                {"single", "Single page", "lucide-rectangle-vertical"},
                {"double", "Facing pages", "lucide-columns-2"},
                {"cover", "Facing, cover first", "lucide-layout-panel-top"}
              ]
            }
            icon={icon}
            active={@menu_value == value}
            phx-click="set_menu"
            phx-value-v={value}
          >
            {label}
          </.menu_item>
        </.ink_menu>

        <.ink_menu id="ui-menu-actions">
          <:trigger class="flex items-center gap-1.5 px-3 h-8 text-xs font-medium rounded-full bg-white/5 hover:bg-white/15 text-gray-300 hover:text-white transition-colors">
            <.icon name="lucide-settings" class="w-3.5 h-3.5" /> Actions
            <.icon name="lucide-chevron-down" class="w-3 h-3" />
          </:trigger>
          <.menu_item icon="lucide-pencil" phx-click="noop">Edit metadata</.menu_item>
          <.menu_item icon="lucide-refresh-cw" phx-click="noop">Rescan</.menu_item>
          <.menu_item icon="lucide-settings" navigate="/dev/ui">A link</.menu_item>
          <.menu_separator />
          <.menu_item icon="lucide-zap" tone="warning" phx-click="noop">Force rescan</.menu_item>
          <.menu_item icon="lucide-trash-2" tone="danger" phx-click="noop">Delete</.menu_item>
        </.ink_menu>

        <.ink_menu id="ui-menu-icon" modal>
          <:trigger
            label="More"
            class="p-1.5 rounded text-gray-500 hover:text-white hover:bg-white/10 transition-colors"
          >
            <.icon name="lucide-ellipsis-vertical" class="w-4 h-4" />
          </:trigger>
          <.menu_label>Modal menu</.menu_label>
          <.menu_item icon="lucide-check" phx-click="noop">Dismiss click is swallowed</.menu_item>
        </.ink_menu>
      </.specimen>

      <.specimen title="Select" note="ink_select — value arrives through the form's phx-change">
        <form id="ui-select-form" phx-change="select_changed" class="flex flex-wrap items-center gap-6">
          <.ink_select
            id="ui-select-sort"
            name="sort"
            label="Sort"
            value={@select["sort"]}
            options={[{"Title A → Z", "title_asc"}, {"Title Z → A", "title_desc"}, {"Newest first", "added_desc"}]}
          />
          <.ink_select
            id="ui-select-publisher"
            name="publisher"
            label="Publisher"
            prompt="All publishers"
            searchable
            value={@select["publisher"]}
            options={for n <- 1..40, do: {"Publisher number #{n}", "p#{n}"}}
          />
          <div class="w-56">
            <.ink_select
              id="ui-select-role"
              name="role"
              label="Role"
              variant="field"
              value={@select["role"]}
              options={[{"User", "user"}, {"Admin", "admin"}]}
            />
          </div>
          <code id="ui-select-state" class="text-xs text-gray-400">{inspect(@select)}</code>
        </form>
      </.specimen>

      <.specimen title="Dialog" note="dialog, dialog_footer — rendered to open, removed to close">
        <.ink_button variant="ghost" size="md" phx-click="toggle_dialog">Open dialog</.ink_button>
        <.dialog :if={@dialog} id="ui-dialog" title="Edit something" on_close={JS.push("toggle_dialog")}>
          <:description>Escape, the ✕ and a click on the backdrop all ask the server to close it.</:description>
          <form phx-submit="toggle_dialog" class="space-y-4">
            <.ink_select
              id="ui-dialog-select"
              name="rating"
              label="Rating"
              variant="field"
              value="teen"
              options={[{"Everyone", "everyone"}, {"Teen", "teen"}, {"Mature", "mature"}]}
            />
            <.dialog_footer>
              <.ink_button type="button" variant="ghost" size="md" phx-click="toggle_dialog">Cancel</.ink_button>
              <.ink_button type="submit" size="md">Save changes</.ink_button>
            </.dialog_footer>
          </form>
        </.dialog>
      </.specimen>

      <.specimen title="Panels and figures" note="panel, stat_list, stat, progress_bar, run_bar">
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
          <.run_bar value={0.62} label="Scan progress" />
          <.run_bar value={nil} label="Working" />
        </.panel>
      </.specimen>

      <.specimen title="Cover" note="hero_cover, media_card">
        <div class="pb-4 pr-16">
          <.hero_cover id="ui-hero-cover" />
        </div>
        <.media_card navigate="/dev/ui" title="Media card" subtitle="2024" badge="#1" progress={0.4} class="w-36" />
        <.media_card
          navigate="/dev/ui#read"
          title="Read, check mark"
          subtitle="2024"
          badge="#2"
          progress={1.0}
          class="w-36"
        />
        <.media_card
          navigate="/dev/ui#stamp"
          title="Read, stamp mark"
          subtitle="2024"
          badge="#3"
          progress={1.0}
          read_mark="stamp"
          class="w-36"
        />
        <.media_card navigate="/dev/ui#pages" title="Book with page count" page_count={128} class="w-36" />
        <.media_card navigate="/dev/ui#series" title="Series" badge="6 issues" type={:series} class="w-36" />
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

      <.specimen title="Flash" note="flash — put_flash/3 shows these bottom right; info clears itself after 6s">
        <.ink_button variant="ghost" size="md" phx-click="flash" phx-value-kind="info">Show info flash</.ink_button>
        <.ink_button variant="ghost" size="md" phx-click="flash" phx-value-kind="error">Show error flash</.ink_button>
      </.specimen>

      <.specimen title="Pagination" note="pagination">
        <.pagination page={@page} total_pages={24} on_page="set_page" />
      </.specimen>

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
