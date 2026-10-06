# UI redesign plan — "ink" design language everywhere

Goal: bring every page up to the look of the search, series, book and reader
pages, built from shared components instead of per-page class strings.

**How to resume:** find the first unticked box, read the phase intro, go. Each
box is sized to be one commit. Tick it in the same commit. Paths are relative
to `stashix_web/`.

Status legend: `[ ]` todo · `[x]` done · `[~]` started, see note · `[-]` dropped, see note

---

## 1. The design language (what we are copying)

Extracted from `search_live.ex`, `series_live.ex`, `book_live.ex`,
`reader_live.ex`, `detail_components.ex`, `metadata_components.ex` and the
second half of `assets/css/app.css`.

| Element | Recipe | Lives today in |
|---|---|---|
| Colour | gray-950 page, violet-600 action, **ink** (`--color-ink`, aqua) as the second highlight: stickers, hard shadows, "you are here", focus | `app.css` `@theme` |
| Display type | Big Shoulders Display, 800–900 weight, uppercase, tight leading (`font-display font-black uppercase leading-none`) | headings, buttons, counters |
| Eyebrow | 10–11px, bold, `tracking-[0.2em]`, uppercase, violet-300 or gray-500 | above every headline / section |
| Ghost numeral | huge outlined number behind the hero (`.ghost-numeral`) | series, search, reader end card |
| Halftone | print-dot texture fading from a corner (`.halftone`) | hero, indicia, end card |
| Cover wash | blurred cover behind the hero (`.detail-backdrop`, `BackdropFade` hook) | `detail_page/1` |
| Ink button | chunky CTA with hard 4px ink offset shadow (`.ink-btn`, `.ink-split`) | series, book, reader |
| Sticker | small rotated ink label, black display text (`.reader-sticker`) | reader bar, end card |
| Indicia panel | violet→ink wash, left ink border, label/value pairs | `indicia/1` |
| Menu | zinc-950 panel, 1px white ring, hard ink shadow, tracked labels, display-type items, ink left bar + check on the active one | `reader_live.ex` `menu_option/1`, `.reader-menu*` |
| Segmented control | joined cells, inset 1px ring, violet fill when active | `.reader-ctl-group`, `ctl_class/1` |
| Pills / chips | rounded-sm or rounded-full, `border-white/15`, hover to ink | search filters, `chips/1`, `picked/1` |
| Links | underlined, `decoration-2 decoration-violet-500 underline-offset-4` | search, series |
| Motion | staggered `.rise` with `--i`, 120ms press on buttons, all behind `prefers-reduced-motion` | `app.css` |
| Shape | `rounded-md` / `rounded-sm`. Not `rounded-xl`. Rings (`ring-1 ring-white/10`) instead of gray borders | everywhere new |

What the old pages still do, and should stop doing: `rounded-xl` gray-900
cards with gray-800 borders, `text-2xl font-bold` sans headings, native
`<select>`, SaladUI dropdowns skinned `bg-gray-800 border-gray-700`,
`indigo-*` buttons (admin, login, setup), violet "pip" section headings
(`w-1 h-5 bg-violet-500`), duplicated breadcrumb markup.

Dark only. `<html class="dark">` is fixed and the new language hard-codes
white-on-black, so no light theme work is planned.

---

## 2. Decisions (settled 2026-10-06)

- [x] **D1 — Menu is our own, no SaladUI.** Audit of real usage: of 24
  imported SaladUI components only five are used — `dropdown_menu` (7 menus),
  `dialog` (2 edit dialogs: `series_live.ex:713`, `book_live.ex`), `alert`
  (1, `login_live.ex`), `separator` (3, browse pages) and `progress`
  (1, `home_live.ex:672`). Everything else
  (toast, tabs, select, slider, …) is imported but never rendered. Replacement
  plan, leaning on the platform instead of a framework:
  - **Menu / select:** native Popover API (`popover` attribute). The top
    layer gives light-dismiss, Escape and "above everything" for free, so no
    portal is needed for the sidebar menu. One `InkMenu` hook (~120 lines)
    positions the panel from the trigger rect (flip/shift at viewport edges)
    and handles arrows, Home/End, type-ahead and focus return.
  - **Dialog:** native `<dialog>` + `showModal()` for focus trap, Escape and
    backdrop; a ~30 line hook opens it on mount and pushes the close event.
    `DialogHistory` stays as is.
  - **Alert, separator, progress:** plain markup (`flash`/`panel`, a `div`,
    `progress_bar`).
- [x] **D2 — Delete it all.** Follows from D1: remove the `salad_ui` dep,
  `lib/stashix_ui/` except `icon.ex`, `lib/stashix_ui.ex`, `assets/js/ui/`
  (~2,700 lines of core + 17 components), `assets/css/salad_ui.css`, the
  `@source` lines for the dep, the `SaladUI` hook and the 24 imports in
  `stashix_web.ex`. Happens in Phase 2 once the last usage is gone. Check that
  `icon.ex` does not depend on `StashixUi.Helpers` before deleting it.
  Still to verify: is `controllers/page_html/home.html.heex` routed at all?
- [x] **D3 — Components live in** `lib/stashix_web/components/ui/`, one module
  per family, imported in `html_helpers/0`.
- [x] **D4 — Wacky ideas are decided one at a time.** Ask before implementing
  each one in section 6; the ★ marks are suggestions, not approvals. Boxes
  that depend on one say **(ask first)**.

---

## 3. Component inventory (target)

`StashixWeb.UI.Ink` — primitives (`components/ui/ink.ex`)

| Component | Replaces |
|---|---|
| `<.ink_button variant="primary\|ghost\|danger\|link" size>` | 4 copies of the ink-btn class string, the "reader-end-alt" ghost button, every `bg-indigo-600` button |
| `<.split_button>` | book page read button |
| `<.icon_button>` | round `bg-white/5` buttons (crumb back, lightbox close, shelf arrows, filter close) |
| `<.eyebrow>` | ~15 hand-written tracked labels |
| `<.display_heading level size count>` | hero `h1`s, `results_heading/1`, "Issues 12" headings |
| `<.ghost_numeral>` | 3 copies |
| `<.sticker>` | reader issue sticker, end-card stickers |
| `<.pill active>` / `<.chip>` | `pill_class/1`, `chips/1`, `picked/1`, format pills, `library_filter/1` buttons |
| `<.panel variant="plain\|indicia\|rail">` | gray-900 cards, `indicia/1` shell, `.filter-rail` |
| `<.stat label value navigate>` | home stat strip, library/publisher tiles, stats tiles, indicia items |
| `<.kbd>` | Ctrl-K hints (navbar, search), reader end card |
| `<.text_link>` | underlined violet links |
| `<.progress_bar>` / `<.run_bar>` | card progress, scan progress, series run |

`StashixWeb.UI.Menu` — overlays (`components/ui/menu.ex`)

| Component | Replaces |
|---|---|
| `<.ink_menu>` + `:label`, `<.menu_item icon active navigate\|on_select danger>`, `<.menu_separator>` | reader view menu; SaladUI dropdowns in `app.html.heex` (library ⋮, activity, user), `home_live.ex:610`, `series_live.ex:431`, `book_live.ex:358` and `:538` |
| `<.ink_select name options value prompt>` | every native `<select>`: `sort_select/1` (5 pages), `series_live.ex:653,793`, `book_live.ex:733`, `search_live.ex:811` + `filter_select/1` ×3, `identify_component.ex:703`, `admin_metadata_live.ex:492,652`, `admin_live.ex:626,751`, `core_components.ex` `input type="select"` |
| `<.segmented>` | `.reader-ctl-group` + `ctl_class/1`, admin publisher tab bar, search type tabs |

`ink_select` is a menu with radio items plus a hidden input; a small hook sets
the value and dispatches a bubbling `input` event so `phx-change` forms keep
working unchanged. Add a `searchable` option for long lists (publishers), which
can share code with the `CreatorCombobox` hook.

`StashixWeb.UI.Page` — page furniture (`components/ui/page.ex`)

| Component | Replaces |
|---|---|
| `<.page cover_src wide fade>` | `detail_page/1` (move + rename, keep an alias until Phase 6) |
| `<.crumbs>` | `detail_crumbs/1`, hand-rolled breadcrumbs in `library_live.ex`, `publisher_live.ex` |
| `<.page_hero eyebrow title count>` | `browse_header/1`, admin/stats `h1`s |
| `<.section title count>` + `:actions` | pip headings, `results_heading/1` |
| `<.shelf id>` | horizontal scroll rows with arrow buttons (home ×3, library ×3, publisher ×3) |
| `<.cover_grid>` | `media_grid/1`, `results_grid/1`, the series issue grid (three different column sets today) |
| `<.empty_state>` | `browse_empty/1` |
| `<.pagination>` | restyle in place |

`StashixWeb.UI.Forms` and `StashixWeb.UI.Data` (`forms.ex`, `data.ex`)

| Component | Replaces |
|---|---|
| `<.field label hint error>`, `<.text_input>`, `<.textarea>`, `<.toggle>`, `<.checkbox>` | `input_class/0` (defined twice), `field_class/0`, ~120 raw inputs in admin/identify/setup/login |
| `<.data_table>` | 8+ hand-written tables in `admin_live.ex`, `admin_metadata_live.ex` |
| `<.tabs>` | admin publishers tab bar, metadata sub-nav |
| `<.dialog>` | `modal/1`, `confirm_dialog/1`, identify dialog shell, cover lightbox |
| `<.flash>` | restyle in place |

`media_card/1` stays in `core_components.ex` and gets restyled (Phase 3).

---

## 4. Phases

Every phase ends with: `mix format`, `mix compile --warnings-as-errors`,
`mix test`, and a look at the touched pages at phone and desktop width.

### Phase 0 — Groundwork

- [x] Resolve D1–D4 above and record the answers in this file.
- [x] Remove the 19 SaladUI imports in `stashix_web.ex` that nothing renders,
  and their JS imports in `app.js` (keep dropdown_menu, dialog, alert,
  separator, progress until Phase 2). Removed the unrouted `PageController`,
  `PageHTML` and `home.html.heex`.
- [ ] Split `assets/css/app.css` into `tokens.css` (theme, fonts), `ink.css`
  (shared primitives), `reader.css`, `search.css`; `app.css` only imports.
- [ ] Rename shared CSS out of page namespaces: `.reader-menu*` → `.ink-menu*`,
  `.reader-ctl-group` → `.ink-segmented`, `.reader-sticker` → `.sticker`,
  `.filter-rail` → `.ink-rail`. Pure rename, no visual change.
- [ ] Add a dev-only style guide at `/dev/ui` (inside the existing
  `dev_routes` block) that renders every component in every variant. Each
  later box that adds a component also adds it here.

### Phase 1 — Primitives (no visual change to pages)

- [ ] `UI.Ink`: `ink_button`, `split_button`, `icon_button`, `text_link`.
- [ ] `UI.Ink`: `eyebrow`, `display_heading`, `ghost_numeral`, `sticker`, `kbd`.
- [ ] `UI.Ink`: `pill`, `chip`, `panel`, `stat`, `progress_bar`.
- [ ] `UI.Page`: `page`, `crumbs`, `page_hero`, `section`, `cover_grid`,
  `shelf`, `empty_state`.
- [ ] Swap the four already-redesigned pages onto the primitives. Output
  should be pixel-identical; this proves the API before the old pages use it.
  - [ ] `series_live.ex`
  - [ ] `book_live.ex`
  - [ ] `search_live.ex`
  - [ ] `reader_live.ex`
  - [ ] `detail_components.ex`, `metadata_components.ex`

### Phase 2 — The menu

- [ ] `UI.Menu.ink_menu` + `menu_item` + `menu_separator` per D1 (Popover
  API + `InkMenu` hook), with the reader look. Keyboard: arrows, Home/End,
  Escape, type-ahead, focus returns to the trigger. Must survive LiveView
  patches while open (the activity menu re-renders during a scan).
- [ ] Reader uses `<.ink_menu>`; delete `menu_option/1`, `layout_menu_open`,
  `toggle_layout_menu`, `close_layout_menu`. Update `reader_live_test.exs`.
- [ ] Replace SaladUI dropdowns:
  - [ ] `app.html.heex` user menu
  - [ ] `app.html.heex` activity menu (scan rows as `run_bar`s: **ask first**)
  - [ ] `app.html.heex` sidebar library ⋮ menu (top layer, no portal)
  - [ ] `home_live.ex` library card ⋮ menu
  - [ ] `series_live.ex` admin menu
  - [ ] `book_live.ex` admin menu
  - [ ] `book_live.ex` read-options menu inside `split_button`; drop the
    `salad_ui:command` close dispatches and the unused `read_menu_open` assign
- [ ] `UI.Menu.ink_select` + hook, including `searchable`.
- [ ] Replace native selects:
  - [ ] `sort_select/1` in `core_components.ex` (covers all_series, all_books,
    all_issues, library, publisher)
  - [ ] `series_live.ex` issue sort (`:653`) and edit form (`:793`)
  - [ ] `book_live.ex:733`
  - [ ] `search_live.ex` sort (`:811`) and `filter_select/1` (role, library,
    publisher — publisher uses `searchable`)
  - [ ] `identify_component.ex:703`
  - [ ] `admin_metadata_live.ex:492,652`
  - [ ] `admin_live.ex:626,751`
  - [ ] `core_components.ex` `input type="select"`
- [ ] `UI.Menu.segmented`; reader fit/direction clusters and search type tabs
  use it.
- [ ] Navbar search results dropdown takes the menu skin.
- [ ] `UI.Data.dialog` on native `<dialog>`; the series and book edit dialogs
  use it (moved up from Phase 3).
- [ ] `login_live.ex` alert, the three browse-page separators and the
  `home_live.ex` progress → plain markup / `progress_bar`.
- [ ] **Remove SaladUI entirely** per D2. `grep -ri salad` returns nothing;
  `mix deps.unlock --unused` drops it from `mix.lock`.

### Phase 3 — App shell and cards

- [ ] Sidebar: extract `<.nav_item>` (9 copies of the same link), display-type
  labels, ink left bar on the active item (same mark as an active menu item),
  eyebrow section labels. Fix the four plain `<a href>` nav links
  (Series/Books/Issues/Publishers) to `<.link navigate>`.
- [ ] Sidebar actually marks the current page (today only admin nav does).
- [ ] Top bar: search box in the `search-headline` family (heavy bottom rule,
  ink caret), `kbd` component, violet→ink rule under the bar like `.reader-bar`.
- [ ] `media_card/1`: `rounded-md`, ring instead of glow, issue number as a
  sticker, `progress_bar`, lucide icons in place of the inline SVGs, "read"
  mark in ink instead of green ("READ" stamp: **ask first**).
- [ ] `pagination/1`: display-type numerals, ink sticker for the current page.
- [ ] `flash/1`: restyle with `panel` + ink border (caption-box look: **ask first**).
- [ ] `modal/1`, `confirm_dialog/1` and the cover lightbox use `UI.Data.dialog`.

### Phase 4 — Browse pages

- [ ] `all_series_live.ex`, `all_books_live.ex`, `all_issues_live.ex`:
  `page` + `page_hero` (title in display type, total as ghost numeral),
  library filter as `pill`s, sort as `ink_select`, `cover_grid`.
- [ ] `all_publishers_live.ex`: extract `<.publisher_card>`; cover strip
  stays, name in display type, counts as `stat`s.
- [ ] `library_live.ex`: `crumbs`, hero with a cover wash from the newest
  cover, stat tiles as an `indicia` panel, `shelf` ×3, sub-pages share the
  browse layout above.
- [ ] `publisher_live.ex`: same treatment; it is a near copy of
  `library_live.ex`, so extract the shared overview + sub-page layout into one
  component both use.
- [ ] `home_live.ex`:
  - [ ] one `<.home_hero>` for both spotlight and continue-reading (the two
    blocks are ~110 duplicated lines), built from `page`, `hero_cover`,
    `ink_button`
  - [ ] stat strip → `stat`s
  - [ ] continue reading / up next / recommendations → `section` + `shelf`
  - [ ] library cards → shared with the publisher card

### Phase 5 — Stats, admin, auth

- [ ] `stats_live.ex`: `page_hero`, summary tiles as `stat`s in an indicia
  panel, chart cards as `panel`s with `section` headings, ECharts theme using
  violet/ink and the display font for axis labels (`Hooks.Chart` in `app.js`).
- [ ] `UI.Forms`: `field`, `text_input`, `textarea`, `toggle`, `checkbox`;
  delete both `input_class/0` helpers and `field_class/0`.
- [ ] `UI.Data`: `data_table`, `tabs`.
- [ ] `admin_live.ex` (1,617 lines), one tab per commit, each moved to its own
  function component or module while it is being restyled:
  - [ ] users
  - [ ] libraries
  - [ ] cleanup
  - [ ] publishers (aliases + visibility)
- [ ] `admin_metadata_live.ex`: sources, settings, review, jobs.
- [ ] `identify_component.ex`: dialog shell, form fields, result rows.
- [ ] `login_live.ex`, `setup_live.ex`: kill the indigo, use `field` +
  `ink_button` (comic-cover layout: **ask first**).
- [ ] Error pages (`error_html.ex`): ink styling (reader ghost: **ask first**).

### Phase 6 — Cleanup

- [ ] `grep -rn "indigo-\|rounded-xl\|bg-gray-800 border-gray-700" lib/` is
  empty or every hit is justified.
- [ ] Remove unused CSS and the `detail_page` alias.
- [ ] No raw `<select>`, no `dropdown_menu` outside `components/ui/`.
- [ ] Accessibility pass: focus rings visible on every interactive component
  (ink ring), menu and select keyboard-only, contrast of gray-500 labels on
  gray-950.
- [ ] `prefers-reduced-motion` covers every new animation.
- [ ] Refresh `priv/static/screenshots` and the README images.

---

## 5. Suggested order if time is short

Phase 0 → Phase 2 (the menu is the specific ask and touches every page) →
Phase 3 (shell + card change every page at once) → Phase 4 → Phase 5.
Phase 1's "swap the redesigned pages" boxes can trail behind, as they change
nothing visible.

---

## 6. Wacky ideas (ask before implementing each, per D4)

★ = suggested; has a natural slot in the phases above. Record keep / drop
next to each idea when it is decided.

- ★ **Flash messages as caption boxes.** Narrator-box rectangles with a hard
  violet offset shadow, tilted one degree, like `.reader-end-caption`. Errors
  get a jagged "burst" edge.
- ★ **Login and setup as a comic cover.** Masthead "STASHIX" in 900-weight
  display type across the top, issue box in the corner showing the app
  version, halftone field, the form sitting where the cover art would be,
  ink-button "OPEN" as the CTA. Setup is "#1 — FIRST ISSUE".
- ★ **Read = a stamp, not a green tick.** Rotated "READ" stamp on cards and
  the book hero, same animation as the reader end stamp.
- ★ **Scan progress as a run bar.** The series run bar reused in the activity
  menu and sidebar: one segment per chunk of files, filling in ink.
- ★ **Error pages are the reader ghost.** "This page isn't there" with the
  hollow dashed page and floating ghost from the end card.
- **Long-box view.** A toggle on browse pages that shows series as comic
  spines in a box (thin vertical strips coloured from the cover blurhash,
  title running up the spine). Hover pulls one out to show its cover.
- **Per-series ink.** Derive an accent from the cover blurhash and set
  `--color-ink` on the series/book page, so every series has its own highlight
  colour. Clamp lightness/chroma to keep contrast.
- **Sound-effect empty states.** "POOF!" / "NOTHING!" in outlined display
  type on a burst shape, instead of a gray icon and a sentence.
- **Stats as a trading card back.** Summary numbers laid out like the stat
  block on the back of a card, the "paper weight" fun fact as a caption box,
  ghost numeral of total pages read behind it.
- **Ctrl-K command palette.** The navbar search becomes a centred palette in
  the menu skin: results, plus actions (scan library, go to admin, toggle
  reading direction).
- **Sidebar as long-box dividers.** Each library is a tabbed divider card;
  the active one sticks up.
- **Page-turn route transitions.** View Transitions API: the cover you click
  grows into the hero cover on the next page (card → `hero_cover` share a
  `view-transition-name`).
- **Halftone skeletons.** Loading placeholders shimmer with moving print dots;
  the top loading bar becomes the violet→ink rule.
- **Variant-cover hover.** On a series card with several covers, hovering
  fans the next two out behind it like `.cover-stack`.
- **Admin as the editor's desk.** Destructive confirms get a red "REJECTED"
  stamp; the metadata review queue is a stack of pages you approve or bin.

---

## 7. Log

Add a dated line when a phase closes or a decision changes.

- 2026-10-06 — plan written; nothing started.
- 2026-10-06 — D1–D4 settled: own menu/dialog on native Popover + `<dialog>`,
  SaladUI removed completely, wacky ideas asked one by one.
