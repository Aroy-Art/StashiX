# Calibre plan — Calibre libraries as a first-class books source

Goal: point a books library at a Calibre library folder and have Stashix
follow it. Calibre stays where metadata is edited; Stashix mirrors
`metadata.db` into Postgres on every change (not a one-off import), serves the
files from Calibre's own folder layout, and later writes edits back.

**How to resume:** find the first unticked box, read the phase intro, go. Each
box is sized to be one commit. Tick it in the same commit. Paths are relative
to `stashix_web/`.

Status legend: `[ ]` todo · `[x]` done · `[~]` started, see note · `[-]` dropped, see note

---

## 1. Where we are (2026-11-19)

Reference library: `jail-arch.lan:/mnt/DataFortress2.0/Storage/MultiMedia/Books/CalibreDB`
(local ZFS on the server). Edited in Calibre on a desktop, then pushed to the
server with **rsync** by hand.

| What | Count / value |
|---|---|
| Books | 678 (`books`) |
| Files | 710 (`data`): PDF 576, EPUB 106, MOBI 14, CBZ 5, AZW3 4, CBR 1 |
| Series / tags / identifiers | 53 / 290 / 469 (google, isbn, amazon, mobi-asin, issn, …) |
| Comments / ratings | 220 / 3 |
| Custom columns | none (yet) |
| Calibre viewer annotations / read positions | 0 / 0 |
| Schema | `user_version` 26, `journal_mode = delete` (no WAL) |
| Extras on disk | `.calnotes/notes.db` (+ `resources/`), `.caltrash/` |

Layout: `<Author>/<Title> (<book id>)/` holding `<Title> - <Author>.<ext>`
per format, `cover.jpg` and `metadata.opf`. `books.path` is the folder,
`data.name` the file stem, `data.format` the upper-case extension.

What Stashix does with this folder today (as a plain books library): the
folder scanner sees every author folder as a series, every `(id)` folder as a
book title, ignores `metadata.opf`, and finds `cover.jpg` as a sidecar image.
Two formats of one book become two books. Metadata matching would ask comic
databases. None of Calibre's metadata comes across.

Rsync facts that shape the design:
- rsync writes `.metadata.db.XXXXXX` and renames it over `metadata.db`: the
  file is replaced whole (new inode), never written in place, so a reader
  never sees half a database — but a handle opened before the rename keeps
  reading the old one.
- Book files and `metadata.db` arrive in rsync's order, so for a while the
  database can name files that are not there yet, or files can exist that
  the database doesn't know.
- Anything Stashix writes into the server copy is overwritten by the next
  push unless the user pulls it back first. Write-back (§7, D11) writes there
  anyway and leaves syncing to the user.

---

## 2. Decisions

- [x] **D1 — Two-way eventually, one-way first** (settled 2026-11-19).
  Phases 1–4 are Calibre → Stashix only. Write-back is Phase 5 (D11).
- [x] **D2 — Library source, not a new kind** (settled 2026-11-19). `libraries.source`
  (`:folders | :calibre`, default `:folders`). A Calibre library is
  `kind: :books, source: :calibre`; its root is the folder holding
  `metadata.db`. The setup wizard and Admin → Libraries offer "Calibre
  library" when the chosen folder has a `metadata.db`. Comics inside it (the
  six CBZ/CBR) still open in the image reader through `content_kind`.
- [x] **D3 — Read a snapshot, never the live file.** (settled 2026-11-19) On change, copy
  `metadata.db` to `<DATA_DIR>/cache/calibre/<library_id>.db`, check the
  stamp (`{mtime, size, inode}`) didn't move during the copy (retry if it
  did), `PRAGMA quick_check`, then open the copy read-only. Stashix never
  holds a lock on Calibre's file, so Calibre is never told "database is
  locked", and an rsync rename mid-read can't matter. 1.7 MB copies in
  milliseconds; even 100k-book libraries are tens of MB.
- [x] **D4 — SQLite via `exqlite`.** (settled 2026-11-19) Precompiled NIF, plain SQL, no Ecto
  repo for it (queries are few and read-only). Alternative was shelling out
  to `sqlite3 -json`: fewer deps, but another binary in the image and
  string-parsing everything.
- [x] **D5 — Full read, fingerprint diff.** (settled 2026-11-19) Each sync reads every book
  (one query per table, joined in Elixir), maps it to Stashix attrs, and
  hashes the result. Only books whose fingerprint changed are written.
  `books.last_modified` alone is not enough: renaming a tag, series or
  author in Calibre changes many books without touching their
  `last_modified`. Cost is a few ms per thousand books.
- [x] **D6 — Identity by Calibre uuid, then id.** (settled 2026-11-19) `books.calibre_uuid` +
  `books.calibre_id` (unique per library). The uuid survives a Calibre
  "rebuild library" that renumbers ids; the id is how the folder name is
  built. Series by `series.calibre_id`; creators by name (they're global
  in Stashix already).
- [x] **D7 — Calibre owns its fields.** (settled 2026-11-19) On a Calibre library, every field
  that comes from `metadata.db` is overwritten by sync, whatever
  `locked_fields` says, and shows read-only in the edit dialog with
  "Edited in Calibre". Stashix-only fields (reader kind, age rating,
  adult, …) stay editable and sync never touches them.
- [x] **D8 — Hands off Calibre's folder.** (settled 2026-11-19) For `source: :calibre`: no
  folder scan, no ComicInfo/MetronInfo write-back, no sidecar files, no
  automatic metadata matching (Calibre has its own downloaders). The
  file watcher watches `metadata.db` only. Stashix only reads there until
  Phase 5.
- [x] **D9 — One book, many formats.** (settled 2026-11-19) Each `data` row is a `BookFile` of
  the same `Book`. The reader opens the preferred format: EPUB > KEPUB >
  AZW3 > MOBI > FB2 > PDF > CBZ > CBR (per-user override later); the book
  page lists every format to read or download.
- [x] **D10 — Change detection: watch + debounce + poll.** (settled 2026-11-19) inotify on the
  library root for `metadata.db` (rsync's rename shows as `moved_to`), a
  stamp poll every 5 minutes as fallback (bind mounts, missed events), and
  a 30 s quiet period before syncing so an rsync push lands first. Files
  the database names but that aren't there yet are kept as *missing*, not
  deleted, and re-checked on the next sync or file event.

- [x] **D11 — Write-back goes straight into the library folder**
  (settled 2026-11-19, was Q1). Stashix writes `metadata.db` and
  `metadata.opf` at the library's root path; getting those changes to and
  from the desktop is the user's job (rsync, Syncthing, a network share —
  Stashix doesn't care). Consequence to state in the UI and docs: a push
  that overwrites `metadata.db` drops Stashix edits made since the last
  pull, so with write-back on, the user syncs both ways.
- [x] **D12 — Books without a Calibre series are standalone**
  (settled 2026-11-19). `type: "standalone"`, no series, as the folder
  scanner does today; author pages group them.
- [x] **D13 — A Calibre library is one kind** (settled 2026-11-19).
  Comics inside it stay under Books in the switcher and open in the image
  reader through `content_kind`. No per-book kind.

### Field mapping

| Calibre | Stashix |
|---|---|
| `title`, `sort` | `title`, `sort_title` (new) |
| authors (link order) | credits, role `Writer` (shown as "Author" in books mode); `authors.sort` → `creators.sort_name` (new) |
| series, `series_index` | series (by `calibre_id`), `issue_number` (decimal, so 1.5 works); no series → `type: "standalone"` |
| publisher | publishers |
| `pubdate` | `cover_date`, `year` (Calibre's `0101-01-01` = unknown → nil) |
| `timestamp` | `added_at` (new) — "recently added" follows Calibre's date, not sync order |
| languages (ISO 639-2, `eng`) | `language` (to ISO 639-1 where one exists) |
| tags | tags |
| rating (0–10, half stars) | `rating` (new, library-level, 0–5 stars); per-user ratings are separate work |
| comments (HTML) | `summary`, sanitised to the tags the book page already renders |
| identifiers | `isbn` + external ids (sources gain Google Books, Amazon, Goodreads, Open Library, ISSN, DOI); `uri` → links; other types not stored |
| `uuid`, `id` | `calibre_uuid`, `calibre_id` |
| `has_cover` + `cover.jpg` | cover / thumbnail, as the sidecar image today |
| `data` rows | `book_files` at `<root>/<path>/<name>.<format lowercase>` |
| custom columns | `calibre_fields` jsonb (Phase 4) |
| `last_modified` | `calibre_modified_at` (shown, not used for diffing) |

---

## 3. Phase 1 — Read-only Calibre library

Ends with: add the CalibreDB folder as a library, every book shows with
Calibre's metadata and cover, edits in Calibre + rsync show up in Stashix
without touching anything.

- [x] Add `exqlite`; fixture: a small `metadata.db` built from Calibre's
  schema (triggers that call `title_sort()` / `uuid4()` stripped, since
  those are Python functions) in `test/support/fixtures/calibre/`, with a
  couple of book folders. *Done:* `Stashix.CalibreFixtures` builds a
  library per test from `schema.sql` (user_version 26, no views or FTS);
  `add_book/2` writes the rows and the `<Author>/<Title> (<id>)/` folder,
  `execute/3` changes it the way Calibre would.
- [x] Migration: `libraries.source`, `libraries.calibre_state` (jsonb:
  stamp, last sync, counts, errors); `books.calibre_id`, `calibre_uuid`,
  `calibre_fingerprint`, `calibre_modified_at`, `sort_title`, `added_at`,
  `rating`; `series.calibre_id`; `creators.sort_name`. Unique indexes
  `(library_id, calibre_id)` on books and series. *Done:* a Calibre file
  that isn't on disk is a `book_files` row with `deleted_at`, the same
  "missing" the Health page already lists; no new column.
- [x] `Stashix.Calibre.Snapshot`: stamp, copy, verify, open read-only
  (D3); refuses unknown schema (`user_version` outside the tested range →
  clear error instead of guessing). *Done:* the stamp adds the SQLite
  header's file change counter (bumped on every commit), and a
  `metadata.db-journal` means busy, so a copy taken mid-write is caught
  even within one second. Schema check is by the tables and columns the
  reader needs (`{:unsupported, ["books.uuid", …]}`), not `user_version`,
  so newer Calibres that only add things keep working. Copies go to
  `CALIBRE_CACHE_DIR` (`<data>/cache/calibre`).
- [x] `Stashix.Calibre.Reader`: books with authors, series, publisher,
  tags, languages, rating, comments, identifiers, formats — plain maps,
  one query per table. *Done:* the reference library (678 books) copies
  in ~60 ms and reads in ~20 ms.
- [x] `Stashix.Calibre.Mapper`: Calibre map → book/series/creator attrs
  per the mapping table; HTML comment sanitising; language codes;
  fingerprint. *Done:* comments become plain text (the book page renders
  summaries as text), so no HTML survives to sanitise. External id
  sources gained Google Books, Amazon, Goodreads, Open Library, ISSN, DOI;
  `uri:`/`url:` identifiers become links; other types (`barnesnoble`,
  `urn`, …) aren't stored — one row per source leaves no room for an
  "Unknown" per type. Formats Stashix can't read (KEPUB, TXT, …) are
  listed in `skipped_formats`.
- [x] `Stashix.Calibre.Sync`: diff by fingerprint (D5), upsert series →
  books → credits/tags/publishers/external ids → files, soft-delete books
  gone from Calibre, keep missing files as missing (D10). Batched
  transactions; one PubSub progress stream like scans.
- [x] Files: stat each `data` file; hash, page count / content kind and
  cover only for new or changed files (size/mtime), reusing the scanner's
  per-file steps. *Done (with Sync, one commit):* a book is visible while
  it's in Calibre and has a file on disk; a book back in Calibre under its
  uuid is revived. Series match by Calibre id when the name still fits,
  else by name (rebuilds renumber them), else by id (renamed). Covers from
  `cover.jpg`, else the preferred file's first page; redone when the
  book's fingerprint or files change. Outcome and counts (added, updated,
  unchanged, removed, missing files, skipped formats, errors) go to
  `libraries.calibre_state`.
- [x] Triggers: watcher on `metadata.db`, debounce, stamp poll (D10);
  "Sync now" and "Full resync" (ignores fingerprints) in Admin →
  Libraries; sync runs where scans run so the queue UI shows it.
  *Done:* a library scan of a Calibre library is a sync (`Scanner`), so
  Scan / Force rescan already are "Sync now" / "Full resync" (relabelled
  with the admin page, below). The watcher re-arms a 30 s timer per
  library on `metadata.db` or any book file event; `Calibre.Poller` checks
  stamps every 5 min (first a minute after boot) and also re-syncs while
  files are missing. Debounce and poll are app env
  (`calibre_debounce_ms`, `calibre_poll_ms`). Known gap, as for folders:
  the watcher only learns of new libraries on restart.
- [x] Guard rails (D8): folder scan, file write-back, sidecars and
  matching skip Calibre libraries; scanner refuses a folder library whose
  root is inside a Calibre library (or the other way round). *Done:*
  `Stashix.Calibre.library?/1`. File and series rescans there queue a
  library sync; `FileWriter.write_book/2` (every write-back and sidecar
  path) is a no-op; match jobs cancel with `:calibre_library`. Overlap is
  refused when the library is saved (create and update), not at scan
  time. A failed cover no longer stops a sync.
- [x] Setup wizard + Admin → Libraries: detect `metadata.db`, offer
  "Calibre library", show last sync, counts and errors. *Done:* typing a
  path that holds a `metadata.db` shows a ticked "Calibre library" box
  (and hides Kind: always books); creating one starts its first sync.
  The row gets a Calibre chip, "Synced … · N books · N files missing",
  unreadable formats and the last error; Scan / Force rescan read "Sync
  now" / "Full resync"; Settings and Match Metadata are hidden. The
  library API returns `source` and takes it on create.
- [x] Edit dialog: Calibre-owned fields read-only with "Edited in
  Calibre" (D7). *Done:* `Stashix.Calibre.book_keys/0` /
  `series_keys/0`; those fields show a Calibre badge instead of the lock
  toggle, read-only, and saving never writes them (nor keeps them as
  locks). Book and series pages hide Fetch / Identify, Lock metadata, the
  publisher and language pushes and issue numbers from filenames; their
  rescan reads "Sync with Calibre" (a normal library sync).
- [x] Browser-check against a copy of the real library; tests for
  snapshot (stamp moves mid-copy), mapper, sync (add / change / rename
  tag / delete / missing file / uuid kept across renumbered ids).
  *Done (2026-11-19):* a copy of the reference library without its PDFs
  (2 GB, 8 PDFs kept): setup wizard → first sync 678 books in ~9 s (a
  full resync ~7 s), 568 files missing as expected; books, book page,
  edit dialog, EPUB / MOBI / PDF / CBZ readers checked. An rsync-style
  replace of `metadata.db` (tag renamed, title changed) synced 30 s later
  in 2.6 s, rewriting the 52 books with that tag. Found and fixed: books
  importing in parallel raced to create the same new author; the reader
  opened a multi-format book's AZW3 instead of its EPUB. Seen, not
  Calibre's: one EPUB whose XHTML uses `&nbsp;` without a DTD fails to
  parse in the text reader.

## 4. Phase 2 — Calibre-native browsing

- [x] Book page: formats list (read in / download each), Calibre rating,
  identifiers as links, "Added" date. *Done:* format pills and the
  per-format download menu were already there; the page now starts on
  the reading order's pick in books libraries (EPUB first; comics keep
  CBZ first). Rating shows as stars, "Added" from `added_at`, and Google
  Books, Amazon, Goodreads, Open Library, ISSN and DOI ids link out.
- [x] Reader picks the preferred format (D9); format switch in the
  reader menu when there are several. *Done:* `Library.text_book_file/2`
  picks by `Media.Formats.reading_order/0` (shared with Sync); the text
  reader's View menu lists every format it can open the book in. Reading
  progress is per book: after a switch the reader resumes by page number,
  not at the exact spot (a CFI only applies to the format that saved it).
- [x] Sort by title sort and author sort (`sort_title`,
  `creators.sort_name`) in books mode; author pages list by series then
  index. *Done:* A → Z / Z → A use `coalesce(sort_title, title)` (folder
  books, without one, are unchanged); "Author A → Z" on the Books page
  and a library's books tab sorts by the first writer's sort name
  (alphabetically first; credits don't keep Calibre's order); date-added
  sorts and the home page's recent books use `added_at` before
  `inserted_at`. Author pages already listed series then number; their
  standalone books now sort by sort title too.
- [x] Search: author, tag, publisher, identifier (`isbn:…`) filters.
  *Done:* author, tag and publisher filters already existed. A query
  that is an identifier — `isbn:…` or a bare ISBN-10/13 (dashes and
  spaces allowed), `goodreads:`, `google:`, `amazon:`/`asin:`,
  `openlibrary:`, `issn:`, `doi:`, plus `metron:`, `comicvine:`, `gcd:` —
  matches that id exactly instead of the text search, on the search page
  and in the API / OPDS search (`Library.identifier_query/1`).
- [x] OPDS: one acquisition link per format, Calibre uuid as entry id
  (`urn:uuid:…`) so KOReader keeps its records. *Done:* per-format links
  already existed; they now come best-first (reading order), Calibre
  books' entries use `urn:uuid:<calibre uuid>` like Calibre's own feed,
  and OPDS search finds ISBNs and other ids.

## 5. Phase 3 — OPF and Calibre layout in folder libraries

For books libraries that aren't a Calibre library: Calibre "Save to disk"
exports, calibre-web libraries copied without the database, and the
reference library if it's ever added as a plain folder.

- [ ] OPF reader: Dublin Core + `calibre:*` meta (series, series_index,
  rating, title_sort, author sort, user metadata) — shares parsing with
  `Media.Epub.package/1`.
- [ ] Folder scanner reads `metadata.opf` in the book's folder (and
  `<stem>.opf`) as a sidecar, above embedded metadata; `cover.jpg` already
  works.
- [ ] Calibre layout detection: `<Author>/<Title> (<n>)/` → one book per
  folder (all formats as its files), author from the parent folder, series
  from the OPF — not the author folder as a series.

## 6. Phase 4 — Custom columns, read status, notes

- [ ] Custom columns: read definitions (`custom_columns` + `display`)
  and values (`custom_column_N`, `books_custom_column_N_link`) for every
  datatype (text, comments, series, enumeration, int, float, bool,
  datetime, rating); store in `books.calibre_fields`, definitions in
  `libraries.calibre_state`. Shown on the book page, searchable as
  `#label:value`.
- [ ] Read status mapping: per library, pick a user and a column (bool
  like `#read`, or int/float like `#progress`); a value changed in Calibre
  since the last sync sets that user's progress (read → 1.0, percent →
  progression). Stashix progress never lowers on its own from Calibre.
- [ ] Notes: `.calnotes/notes.db` → creator bio, series summary, tag and
  publisher notes (HTML sanitised; images from `resources/` served like
  covers). `authors.link` / `series.link` → creator / series URL.
  Migration: `creators.bio`, `creators.url`.
- [ ] Calibre viewer data (`annotations`, `last_read_positions`) → the
  mapped user's annotations / progress (EPUB CFI fits the D6 locator).
  Empty in the reference library; low priority.

## 7. Phase 5 — Write-back (D11)

- [ ] Per-library "Write edits back to Calibre" switch (off by default),
  with the D11 warning; conflict rule: a Calibre change that arrives by
  sync after a Stashix edit wins if its `last_modified` is newer, Calibre
  wins on a tie.
- [ ] Write edited fields to `metadata.db`: in a short transaction on the
  live file, only when its stamp matches the last snapshot, with Python-side
  functions (`title_sort`, `uuid4`, …) emulated by registering them or by
  setting the columns those triggers would.
- [ ] Rewrite `metadata.opf` for written books (Calibre's backup format),
  mark them dirty in `metadata_dirtied` so Calibre refreshes them.
- [ ] Read status and progress back to the mapped custom column.
- [ ] Edit dialog: Calibre-owned fields become editable when write-back
  is on for the library.

---

## 8. Later

- Calibre virtual libraries (`preferences.virtual_libraries`) and saved
  searches as Stashix filtered views.
- Kobo sync: use `calibre_uuid` as the Kobo entitlement id, so a device
  that was synced by Calibre/calibre-web keeps its books and progress.
- KEPUB conversion cache for Calibre EPUBs (shared with the Kobo plan).
- Several Calibre libraries at once (each its own Stashix library — D2
  already allows it; check the switcher and duplicate detection across
  them).

---

## 9. Open questions

None open. Settled ones moved to §2 (D1, D11–D13).
