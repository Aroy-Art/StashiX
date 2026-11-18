# Reader formats plan — PDF and EPUB, streamed

Goal: read text PDFs and reflowable EPUBs properly, without the browser ever
loading a whole file. The browser asks for byte ranges (PDF) or single zip
entries (EPUB). Comics keep the current image reader.

**How to resume:** find the first unticked box, read the phase intro, go. Each
box is sized to be one commit. Tick it in the same commit. Paths are relative
to `stashix_web/`.

Status legend: `[ ]` todo · `[x]` done · `[~]` started, see note · `[-]` dropped, see note

---

## 1. Where we are (2026-11-17)

| Format | Today | Problem |
|---|---|---|
| CBZ/CBR/CB7 | `/api/books/:id/page/:n` serves one image | `Extractor.get_page/2` calls `list_pages/1` on **every** request, so CBR/CB7 run `unrar lb` / `7z l` per page |
| PDF | same endpoint, `pdftoppm -r 150` into a temp dir per page | per-page `pdfinfo` too; fixed 150 dpi is blurry on zoom; no text select, search, outline; no cache |
| EPUB | handled as an image archive (`list_archive_pages/1`) | image-only EPUBs work but in name order, not spine order; **text EPUBs show 0 pages** |
| Progress | `reading_progress.current_page :integer` | no meaning for reflowable text |

Most PDFs in the library are scanned comics today, but the target includes
text PDFs and novels: a library switcher (comics/manga vs books) is planned
(see §7), so the reader has to be good at both.

---

## 2. Decisions

- [x] **D1 — Stream, don't download.** The client never fetches a whole book.
  PDF goes through HTTP `Range`; EPUB through a per-entry endpoint.
- [x] **D2 — PDF.js renders text PDFs client-side**, in `TextReaderLive`
  (D7). Range requests with
  `disableAutoFetch: true, disableStream: true`. Works on non-linearized files
  (reads the trailer + xref first, then only needed objects). Gives crisp
  text at any zoom, selection, search and outline. Vendored in
  `assets/vendor/` like echarts; worker as a separate static file.
- [x] **D3 — Scanned PDFs stay server-rendered** (settled 2026-11-17).
  `content_kind: :images` PDFs keep going through `/page/:n` + `pdftoppm` in
  the image reader (`ReaderLive`), with the Phase 1 fixes. They have no text
  to select, so PDF.js would add weight for nothing. `pdftoppm` also serves
  covers, thumbnails and clients that want images (OPDS-PSE, §8).
- [x] **D4 — foliate-js for EPUB** (MIT, maintained, plain ES modules, no
  build). Its loader interface (`loadText`, `loadBlob`, `getSize`) is wired to
  our entry endpoint. epub.js rejected: unmaintained since 2022.
- [x] **D5 — EPUB content is untrusted HTML.** Entry responses carry
  `Content-Security-Policy: sandbox; script-src 'none'` and
  `X-Content-Type-Options: nosniff`; rendering iframes use `sandbox` without
  `allow-scripts`. A malicious EPUB must not reach the session.
- [x] **D6 — Progress becomes a locator.** Readium-style
  `%{"type" => "epub" | "pdf" | "image", "href", "cfi", "page", "progression"}`
  plus a `progression` float column for sorting / progress bars. Same shape
  later feeds OPDS 2 and Kobo sync.
- [x] **D7 — Separate `TextReaderLive`** for reflowable EPUB and text PDF
  (settled 2026-11-17). Text settings (font, size, margins, line height,
  theme) share almost nothing with comic layouts; `ReaderLive` stays the
  image reader.
- [x] **D8 — Reader choice: auto-detect + library kind + manual override**
  (settled 2026-11-17). `book_files.content_kind` (`:images | :text`) is set at
  scan: fixed-layout EPUB (`rendition:layout` `pre-paginated`) or PDF without a
  text layer (`pdffonts` / `pdftotext` on a few pages) → `:images`. When
  detection is unsure, library kind (§7) breaks the tie. Per-book override in
  the edit dialog, and it survives rescans (`locked_fields`).

- [x] **D9 — Text reader layout** (settled 2026-11-17). Continuous scroll by
  default (one page and two pages in the View menu); contents and search in
  one left side panel; page themes Paper / Sepia / Night in the View menu,
  saved per user.

---

## 3. Phase 1 — Server fixes (no visible change)

- [x] Cache page lists in ETS keyed by `{path, mtime, size}`;
  `Extractor.get_page/2` uses it. Invalidate on rescan. — `Media.PageCache`;
  stamp is `{mtime, size, inode}`, so a rescanned or replaced file just
  misses (no explicit invalidation). `Extractor.cached_pages/1` serves the
  reader and API; scanner and integrity checks keep the uncached
  `list_pages/1`.
- [x] PDF page count from `book.page_count` / cache, not `pdfinfo` per page.
  — covered by the page list cache.
- [x] `pdftoppm -singlefile` to stdout (or `vips pdfload`), no temp dir.
  — no output root at all is what makes pdftoppm write to stdout
  (`-singlefile -` writes a file named `-.jpg`).
- [x] Width-aware PDF raster (`?w=` → `-scale-to-x`, clamped, bucketed) with
  an on-disk cache next to thumbnails. — widths 480/800/1200/1600/2400;
  `Media.RenderCache` in `PAGE_CACHE_DIR` (`<data>/cache/pages`), pruned
  daily after 14 days unused. Reader sends `srcset`/`sizes` for PDF pages,
  so the browser picks the width (DPR included).
- [x] Tests: page list cache hit/miss, invalidation, PDF page render.
  — `page_cache_test.exs`, `render_cache_test.exs`, PDF cases in
  `extractor_test.exs` (generated PDFs, skipped without poppler).

## 4. Phase 2 — Text PDF reader (PDF.js in `TextReaderLive`)

Scanned PDFs are not touched here: they stay in `ReaderLive` on
server-rendered pages (D3). This phase also lays down `TextReaderLive` and the
routing that Phase 3 reuses for EPUB.

- [x] Migration: `book_files.content_kind` (`:images | :text`, nullable =
  unknown) + per-book override (D8). — override is `books.content_kind`, a
  column scans never write, so it needs no lock; `Library.reader_kind/2`
  resolves override → detected → `:images`. "Reader" select in the edit
  dialog's ComicInfo extras tab.
- [x] Scanner: PDF detection — text layer present (`pdffonts` / `pdftotext`
  on a few sampled pages) → `:text`, else `:images`; unsure → library kind,
  then `:images`. Override field in the book edit dialog, kept on rescan.
  — `Media.ContentKind`: `pdftotext` over the first 6 pages, ≥ 400 non-space
  chars/page → text, ≤ 40 → images, between → nil (OCR'd comics). The
  library-kind tiebreak waits for `libraries.kind` (§8); nil reads as
  images. Existing books need a forced rescan to get detected.
- [x] Reader routing: `/read/:id` picks `ReaderLive` or `TextReaderLive` from
  the effective `content_kind`.
  — `Library.text_book_file/2`; `ReaderLive` redirects to `/read/:id/text`,
  which sends books that open as pages back.
- [x] `GET /api/books/:id/file` with `Range` support: parse header, `206` via
  `send_file/5`, `Accept-Ranges`, `Content-Range`, `ETag`, `416` on bad
  ranges, access check like `page/2`. OpenApiSpex operation.
  — `BookFileController`. Serves only files that open in the text reader
  (settled 2026-11-17): they can't be read any other way, while comics and
  scans stay behind `can_download`. Several ranges → whole file (200).
- [x] Vendor PDF.js (`pdf.min.mjs` + worker) in `assets/vendor/`; serve the
  worker from `priv/static`. — all of it lives in
  `priv/static/vendor/pdfjs/` (6.5.438, Apache-2.0, ~5 MB with fonts, cmaps
  and wasm image decoders) and is imported at runtime, keeping it out of
  `app.js`. Update with `scripts/update-pdfjs.sh <version>`.
- [x] `TextReaderLive` shell: top/bottom bars, exit, progress save, end card
  and next book — same "ink" chrome as `ReaderLive`, text-reader settings.
  — settings saved as `text_layout` / `text_fit` / `text_theme`;
  `save_reader_settings` now merges, so the two readers keep each other's
  keys. Exit handling shared via `assets/js/reader_exit.js`.
- [x] `PdfReader` hook: open document via range transport, render visible
  page(s) to `<canvas>` at devicePixelRatio, text layer for selection.
  — `assets/js/hooks/pdf_reader.js`; DPR capped at 2. Browser-checked:
  a 1.6 MB PDF opened with 6 range requests of 128 KB.
- [x] Layouts: continuous scroll and paged (single / two-up); zoom and fit
  width / fit page. Progress stays page-number based (+ `progression`).
  — scroll (default), one page, two pages (D9). `progression` waits for
  Phase 4.
- [x] Render only visible pages ± neighbours; release canvases far away.
  — IntersectionObserver with a one-screen margin; pages leaving it free
  their canvas and text layer.
- [x] Outline (TOC) panel and in-document search.
  — one left panel with Contents / Search tabs (D9), a bottom sheet on
  phones. Search reads page text in turn, stops at 500 hits, and marks hits
  inside the text layer.
- [x] Data saver: lower render scale, no neighbour prefetch.
  — pixel ratio 1, no margin. Not browser-checked.

## 5. Phase 3 — EPUB reader

- [x] `GET /api/books/:id/epub/*entry`: one zip entry, content type from
  extension / OPF manifest; only names in the archive listing (no traversal);
  D5 headers; cache headers.
  — `EpubController`, plus `GET /api/books/:id/epub` listing entries and
  sizes (the loader's `getSize`). Text books only, like `/file`.
- [x] Keep zip central directory per open book in ETS (`:zip.zip_open`
  handle or offsets) so each entry read is a seek, not a re-list.
  — `Media.Epub` keeps the `unzip` directory (and the parsed package) in
  `PageCache`, now keyed by path and kind; each read opens the file itself.
- [x] Spine order for image-only EPUBs (parse `container.xml` → OPF spine)
  instead of `Enum.sort/1`.
  — `Epub.pages/1`: each spine document's picture; falls back to the
  sorted image listing when the package can't be read.
- [x] Vendor foliate-js; `EpubReader` hook with a custom loader against the
  entry endpoint.
  — pinned commit in `priv/static/vendor/foliate` (`scripts/update-foliate.sh`).
  Browser-checked: opening fetched the package, nav, CSS and only the
  chapter being read. The reader route runs under a nonce CSP in its own
  `live_session` (`Plugs.ReaderCSP`): a book's `<script>` and `onerror`
  were blocked.
- [x] Text reader UI: paginated / scrolled, font, size, line height, margins,
  theme (light/dark/sepia from tokens), TOC, footnote popups.
  — pages (two columns when wide) or scroll; size via the +/− buttons and
  keys; book's own / serif / sans; Paper / Sepia / Night shared with PDF.
  Side taps turn pages. Footnotes open in a popup. Resume is exact (CFI in
  localStorage) when this browser saved the spot, else by share of the book;
  Phase 4 moves the CFI to the server.
- [x] Per-user text settings in `reader_settings` (separate keys from comic).
  — `epub_layout`, `epub_font`, `epub_spacing`, `epub_margins`,
  `epub_size`; theme shared as `text_theme`.
- [x] Scanner: EPUB `content_kind` detection (`rendition:layout`
  `pre-paginated` → `:images`); routing and override already exist (Phase 2).
  — also images when every spine document only wraps a picture (≤ 200
  chars of text). Integrity check accepts text EPUBs without pictures.
- [x] Scanner: page count for text EPUBs is meaningless — store spine length
  or estimated pages; book cards show % instead.
  — stores foliate-js locations (linear content bytes / 1500), the unit the
  reader reports progress in, so existing progress maths and cards work.

## 6. Phase 4 — Progress locators

- [x] Migration: `reading_progress.locator :map`, `progression :float`.
  Backfill `progression = current_page / page_count`.
  — backfilled as `current_page / (page_count - 1)`, so the last page is
  1.0 like the old "read" test (`current_page >= page_count - 1`); books
  with ≤ 1 page and a page past 0 count as read.
- [x] `Library.update_progress` accepts a locator; comic path keeps writing
  `current_page`.
  — `update_progress(access, user, book, page, locator:, progression:)`;
  progression defaults from the page. Comic reader saves
  `%{"type" => "image", "page" => n}`, PDF `"pdf"`, EPUB the CFI and
  section href with foliate-js's fraction. The EPUB reader now resumes from
  the server's CFI (localStorage dropped), so other devices open at the
  exact spot. Browser-checked in a fresh profile.
- [x] Continue-reading rows and progress bars read `progression`.
  — also read status filters, "Up next", stats, the book page, series runs
  and "start over" on the next book. An EPUB is read when the end card
  shows (1.0), not at its last location.
- [x] API: progress endpoint accepts and returns the locator.
  — `GET /api/books/:id/progress` added; `PUT` and the channel's
  `update_progress` take `locator` and `progression`. Unknown locator
  fields are dropped (`ReadingProgress.opts_from_params/1`).

## 7. Phase 5 — Annotations, extra formats, offline, TTS

In scope (settled 2026-11-17). Order inside the phase is open.

### Highlights and notes — text and image readers

- [ ] `annotations` table: `user_id`, `book_id`, `book_file_id`, `locator`
  (D6), `kind` (`:highlight | :note | :bookmark`), `color`, `text` (quoted
  selection), `note`, timestamps.
- [ ] Text reader: highlight a selection (EPUB CFI range / PDF.js text-layer
  quads), add a note, colours, list + jump in a side panel.
- [ ] Image reader: highlight a **region** on a page — locator
  `%{"type" => "image", "page" => n, "rect" => [x, y, w, h]}` in 0..1 page
  coordinates so it survives fit modes and zoom; drawn as an overlay in
  single/double/webtoon; note attached to the region.
- [ ] Bookmarks (page or CFI) in both readers.
- [ ] Export (Markdown / JSON); later mapped to Kobo/OPDS where possible.

### MOBI / AZW3 / FB2

- [x] Add formats to `@supported_formats`, `BookFile` enum, `Archive`/
  `Extractor` routing (MOBI/AZW3 are not zips: serve via `/file` + `Range`,
  foliate-js parses client-side; FB2 is single XML, `.fb2.zip` via entries).
  *Done:* `.mobi .azw3 .azw .fb2 .fbz .fb2.zip`, all named in one place
  (`Stashix.Media.Formats`). Kindle books open from byte ranges (the hook
  hands foliate-js a File stand-in whose slices are `Range` requests); FB2
  is fetched whole, `.fbz`/`.fb2.zip` unzipped by `/file`. Always text.
  Locator `type` is `mobi` / `fb2`, with a CFI as for EPUB.
- [x] Metadata + cover extraction for each (EXTH records, FB2
  `<description>`). *Done:* `Stashix.Media.Mobi` / `Stashix.Media.Fb2`
  (title, authors, translators, FB2 sequence → series + number, summary,
  publisher, year, language, ISBN, genres; cover as the thumbnail).
  CP1251 FB2 descriptions keep only their ASCII (no decoder in Erlang).
- [x] DRM'd files: detect and show a clear "can't open" instead of failing.
  *Done:* PalmDOC encryption flag → the reader says the book is
  DRM-protected; the integrity check flags it, and KFX `.azw` as unreadable.

### Offline reading

- [ ] Service worker caching fetched ranges / entries / pages per book.
- [ ] "Download for offline" action that walks the spine or page list;
  storage quota display and eviction.
- [ ] Progress and annotations queue offline, sync on reconnect (locator
  `updated_at` wins).

### Read-aloud (TTS)

- [ ] foliate-js TTS via Web Speech API: play/pause, speed, voice, follows
  and highlights the current sentence, page turns along.
- [ ] Text PDFs: same from the PDF.js text layer.

---

## 8. Roadmap (after the readers)

### Library switcher (comics/manga vs books)

- [ ] `libraries.kind` (`:comics | :books`), picked at creation.
- [ ] Switcher in the nav; home, browse and search filter by kind.
- [ ] Kind sets defaults: reader (image vs text), metadata sources, card
  shape, labels ("issue" vs "book").

Order: library switcher → OPDS → Kobo sync (settled 2026-11-17; Kobo reuses
OPDS's per-user tokens and feed queries).

### OPDS

- [ ] OPDS 1.2 catalog (Atom): root, libraries, series, new, search
  (OpenSearch), acquisition links to `/file`.
- [ ] OPDS-PSE page streaming for comics, on top of `/page/:n` (`{pageNumber}`,
  `{maxWidth}` templates) — Panels, Chunky, KOReader.
- [ ] OPDS 2.0 (JSON) feeds + Readium progression where clients support it.
- [ ] Auth: HTTP Basic or per-user API tokens (not the session cookie).

### Kobo sync

- [ ] Per-user sync token, device URL `/kobo/:token/` (Kobo store API
  emulation, as Calibre-Web / Komga do).
- [ ] `v1/library/sync` with sync tokens for incremental changes; proxy
  unknown store calls upstream.
- [ ] KEPUB delivery: convert EPUB with `kepubify` on demand, cached.
- [ ] Reading state both ways, mapped to the D6 locator.
- [ ] Shelves ↔ collections / reading lists.

---

## 9. Open questions

- Annotations on comics: per page only, or also linked across formats of the
  same book (CBZ vs PDF of one issue)?
- Offline: which storage limit per device is acceptable by default?
