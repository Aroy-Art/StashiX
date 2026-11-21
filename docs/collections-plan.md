# Collections plan — user-made groups of books and series

Goal: let each user gather books and whole series into named, ordered
collections ("To read", "Crisis on Infinite Earths", "Book club"), share one
with others when they want, and see the same collections everywhere they
read: the web UI, OPDS apps, and a Kobo's shelves (both ways). Rule-based
("smart") collections follow once manual ones work.

**How to resume:** find the first unticked box, read the phase intro, go. Each
box is sized to be one commit. Tick it in the same commit. Paths are relative
to `stashix_web/`.

Status legend: `[ ]` todo · `[x]` done · `[~]` started, see note · `[-]` dropped, see note

---

## 1. Where we are (2026-11-21)

- Grouping today: libraries, series, publishers, creators, and story arcs
  (`BookStoryArc`: `name`, `arc_number`, from ComicInfo / MetronInfo) shown
  on book pages. Nothing the user makes.
- Per-user state that exists: reading progress (`ReadingProgress`), annotations,
  UI settings. Access is per library with age ratings (`Library.Access`); every
  list goes through it.
- Clients that could carry collections: OPDS 1.2 / 2.0 (`OpdsController`, one
  feed builder, two renderers), Kobo sync (`KoboController`; shelves are
  "tags" in the store API, store calls are proxied to Kobo), KOReader (kosync
  has no collections; KOReader's own collections stay on the device).
- No drag-and-drop code in `assets/js` yet.

## 2. Decisions

- [x] **C1 — A collection holds books and series** (settled 2026-11-21). A
  series entry stays live: issues added to the series later are in the
  collection without anyone adding them. Clients without series (Kobo, OPDS
  acquisition feeds) see the collection expanded to books.
- [x] **C2 — Personal, shareable** (settled 2026-11-21). Every collection has
  one owner. The owner can mark it shared: then every user sees it, read-only,
  limited to the books they may read (C5). Only the owner edits.
- [x] **C3 — Manual order** (settled 2026-11-21). Entries have a position the
  owner arranges (a reading order for an event or crossover). Viewers can
  still sort by title, year or date added; "Collection order" is the default.
- [x] **C4 — Smart collections later** (settled 2026-11-21). Planned in §8,
  built after phases 1–6. The data model leaves room (`kind`, `rules`).
- [x] **C5 — What a viewer sees.** (settled 2026-11-21, as proposed): a collection's books are its
  entries expanded (series → their books in issue order), deduplicated (a book
  listed alone and in a listed series appears once, at its first spot), and
  filtered by the viewer's `Access` — so a shared collection never shows a book
  someone may not read, and the count is the viewer's count. A shared
  collection a viewer can read nothing of is hidden from them.
- [x] **C6 — Names unique per owner.** (settled 2026-11-21, as proposed): yes (case-insensitive). Kobo
  shelves are matched by id, but the device UI shows names only, and two
  "To read" collections would be confusing everywhere.
- [x] **C7 — The library switcher.** (settled 2026-11-21, as proposed): collections are not narrowed by
  Comics / Books; they're the user's own mix. The collections list shows all;
  inside one, everything shows. (A "Comics only" filter inside is cheap later.)
- [x] **C8 — Reordering.** (settled 2026-11-21, as proposed): vendor SortableJS (MIT, ~45 KB, touch and
  keyboard friendly) in `assets/vendor/` like echarts, behind a `Sortable`
  hook; plus "Move to top / bottom" in each entry's menu for long lists and
  phones. Positions are integers with gaps (1024 apart), renumbered when a gap
  runs out.
- [x] **C9 — Kobo shelves scope.** (settled 2026-11-21, as proposed): a device gets the user's own
  collections as shelves, not other people's shared ones (a shelf on the device
  would look editable but edits couldn't stick). A setting to include shared
  ones can come later.
- [x] **C10 — Shelves made on the Kobo.** (settled 2026-11-21, as proposed): a shelf created on the
  device becomes a Stashix collection when it holds at least one Stashix book
  or is empty; a shelf of only Kobo store books stays at Kobo (proxied).
  Store books added to a Stashix-backed shelf are dropped from it on the
  Stashix side (Stashix can't hold them) — noted in the UI.

## 3. Data model

```
collections
  id            uuid pk
  user_id       uuid → users, on delete cascade        (owner)
  name          string, not null                       (unique per user, lower(name))
  description   text
  shared        boolean, default false
  kind          string, default "manual"               ("smart" in §8)
  rules         jsonb                                  (§8; null for manual)
  default_sort  string, default "position"             (position | title | year | added)
  timestamps    (updated_at bumps on any entry change — Kobo/OPDS "modified")

collection_entries
  id            uuid pk
  collection_id uuid → collections, on delete cascade
  book_id       uuid → books,  on delete cascade, null
  series_id     uuid → series, on delete cascade, null
  position      integer, not null
  inserted_at   utc_datetime                           (the "added" sort)
  check: exactly one of book_id / series_id
  unique (collection_id, book_id), unique (collection_id, series_id)
  index (collection_id, position)
```

Deleting a book or series removes its entries (cascade); a soft-deleted book
(`deleted_at`) is just filtered out like everywhere else.

## Phase 1 — Data and context

- [x] Migration + schemas (`Stashix.Library.Collection`,
      `Stashix.Library.CollectionEntry`), changesets (name 1–120 chars, unique
      per owner, description ≤ 4000).
- [x] `Stashix.Collections` context: `list_for(user, access)` (own + shared
      visible, with the viewer's book count and up to 4 cover book ids for the
      card), `get!(user, access, id)` (owner or shared-and-visible),
      `create/update/delete` (owner only), `add_book/add_series`,
      `remove_entry`, `move_entry(entry, to_index)` (gap positions, renumber
      when needed), `books(access, collection, sort)` (C5 expansion, paged),
      `collections_with(user, book_or_series)` (for the picker's ticks).
      *Done as:* `list_for/2`, `own/1`, `get/3`, `create/update/delete`,
      `add/4` and `remove/3` (`{:book | :series, id}`), `remove_entry/3`,
      `move/4`, `entries/2`, `books/4`, `expanded_ids/2` (one UNION query
      for many collections), `containing/2` (`:direct` / `:series` ticks),
      `holding_book/3` (book page line).
- [x] Tests: ownership (others can't edit, can see only when shared), C5
      expansion/dedup/filtering incl. age-rating limits, live series entries,
      ordering and renumbering, cascades.

## Phase 2 — Web UI

Settled with mockups (2026-11-21): the picker is a popover checklist (bottom
sheet on phones) with a search box over the user's collections; the
collection page is a cover grid; "Collections" sits in the nav right after
Search, and a UI setting adds a sidebar section listing the user's
collections. The mockups as shown:

```
Book page  ⋯ menu  /  [+ Collection] button          Picker (popover / sheet on phones)
                                                     ┌──────────────────────────────┐
                                                     │ Add "Saga #12" to…           │
                                                     │ ☑ To read                    │
                                                     │ ☐ Space operas               │
                                                     │ ☐ Book club                  │
                                                     │ ───────────────────────────  │
                                                     │ + New collection…            │
                                                     └──────────────────────────────┘
Collection page
┌───────────────────────────────────────────────────────────────────────┐
│ COLLECTION · shared by sam                        [Sort: Collection ▾] │
│ Crisis on Infinite Earths                 12 books · 3 series · 41%    │
│ The 1985 event in reading order.                  [Read next ▸] [⋯]    │
├───────────────────────────────────────────────────────────────────────┤
│ ⠿ [cover] Crisis #1   ⠿ [cover] Flash #… ⠿ [stack] Infinity Inc (ser.) │
└───────────────────────────────────────────────────────────────────────┘
```

- [x] Nav item "Collections" (`/collections`): grid of collection cards
      (stacked covers like series cards), sections "Yours" and "Shared with
      you", a "New collection" button, empty state that explains how to add.
- [x] Collection page (`/collection/:id`): hero (name, description, owner
      when shared, counts, read share), entries as book and series cards in
      collection order, sort menu, "Read next" (first unfinished book in
      collection order), owner menu: rename / edit description / share toggle
      / delete (confirm). *Done:* also "Opens sorted by" (default sort) in the
      edit dialog, and Move to top / bottom and Remove in each card's menu.
- [x] Add-to picker on book and series pages (and the cards' menus where they
      have one): ticks for collections that hold it, toggles in place,
      "New collection…" inline. Series page wording: "Add the whole series".
      *Done as:* `CollectionPicker` (LiveComponent) on the book and series
      action rows, filter box over the user's collections, "via series" half
      ticks; "New collection…" opens a small dialog that makes it and adds the
      item. Cards have no menu yet (bulk add in phase 6 covers grids).
- [ ] Sidebar section (UI setting, off by default): the user's collections
      by name under Libraries.
- [x] Reordering (C8): `Sortable` hook on the owner's collection page in
      "Collection order" sort, `move_entry` on drop; Move to top / bottom in
      entry menus; remove from collection. *Done:* `SortableList` hook
      (`assets/js/hooks/sortable_list.js`), SortableJS 1.15.7 vendored as
      `assets/vendor/sortable.min.js` and fetched only when a list mounts;
      long press starts a drag on touch screens.
- [x] Book page: "In collections: To read, Book club" line (own + visible
      shared), linking each.
- [ ] Search finds collections by name (own + visible shared) as a section.
- [ ] Tests (LiveView): create, add/remove from picker, reorder events, share
      toggle visibility for a second user, read-only for non-owners.

## Phase 3 — REST API

- [ ] `/api/collections` (index, show with entries, create, update, delete),
      `/api/collections/:id/entries` (add book/series, remove, move), with
      OpenApiSpex schemas and the same ownership rules. Tests.

## Phase 4 — OPDS

- [ ] "Collections" in both catalogs' root: a navigation feed of the viewer's
      collections (own + shared), each an acquisition feed of its books in
      collection order (C5 expansion), paged; works through the existing
      `OpdsController` feed maps, so 1.2 and 2.0 come together. Tests.

## Phase 5 — Kobo shelves

The store API calls shelves tags: sync items `NewTag` / `ChangedTag` /
`DeletedTag`, each `%{"Tag" => %{"Id", "Name", "Type" => "UserTag",
"Created", "LastModified", "Items" => [%{"RevisionId" => book_id, "Type" =>
"ProductRevisionTagItem"}]}}`; the device edits through `/v1/library/tags`.

- [ ] Server → device: `kobo_synced_collections (app_password_id,
      collection_id, synced_at, items_hash)`; each sync, after books, sends new /
      changed (name, or the hash of its expanded, device-held book ids) /
      deleted collections (C9: own only). Items are only books the device has
      (EPUB, downloadable), so a comics collection may be an empty shelf.
- [ ] Device → server: `POST /v1/library/tags` (create, C10), `PUT
      /v1/library/tags/:id` (rename), `DELETE /v1/library/tags/:id`, `POST
      /v1/library/tags/:id/items` and `…/items/delete` (add / remove books);
      ids that aren't Stashix collections go on to Kobo through the proxy.
      Device-made changes are marked synced so they don't bounce back.
      Removing a book that comes from a series entry: proposal — turn that
      series entry into its remaining books (the device can't remove "part of a
      series"), with a note in the UI history.
- [ ] Tests with the stubbed store: shelf round trips, store-book shelves
      proxied, rename/delete both ways, series expansion on the device.

## Phase 6 — Polish

- [ ] Home: a "Collections" shelf (own, recently changed) when the user has
      any; continue reading shows "in Crisis on Infinite Earths" context?
      (decide then).
- [ ] Bulk add: select mode on book/series grids → "Add to collection".
- [ ] Collection cover: owner can pick one (else the first entries' covers).
- [ ] Download a collection as ZIP (reuses `DownloadController`; download
      permission per book).

## 8. Smart collections (after phases 1–6)

`kind: "smart"`, `rules` jsonb, evaluated as an Ecto dynamic query over
`Access.books(viewer)` — membership is computed, never stored.

```json
{"match": "all",
 "conditions": [
   {"field": "story_arc", "op": "is", "value": "Crisis on Infinite Earths"},
   {"field": "read_status", "op": "is", "value": "unread"}],
 "sort": "story_arc_number", "limit": null}
```

Fields: story arc, tag, genre, publisher, creator (+ role), library, series,
language, format, age rating, read status (unread / reading / read, the
viewer's), rating, year range, added within N days, page count.

- [ ] Rules schema + evaluator (`Stashix.Collections.Rules`), validated
      changeset, tests per field.
- [ ] Editor UI on the collection page (conditions builder; ASCII mockup
      first), live count preview.
- [ ] "Make a collection" from a story arc (and tag / genre / creator) pages:
      a smart collection pre-filled with that rule, sorted by arc number.
- [ ] Smart collections in OPDS and as Kobo shelves (read-only: device edits
      to a smart shelf are refused / ignored; membership changes push as
      `ChangedTag` via `items_hash`).

## 9. Open questions

- Should a shared collection's owner see who can see it (the users who can
  read at least one of its books)?
- Collaborative collections (several editors) — out of scope unless asked.
- Calibre: Calibre has no collections (Calibre-Web's shelves live in its own
  database), so nothing to import; a Calibre tag could seed a smart collection
  via §8 instead.
- KOReader keeps its collections on the device and kosync carries none; OPDS
  collection feeds (phase 4) are how KOReader sees Stashix collections.
