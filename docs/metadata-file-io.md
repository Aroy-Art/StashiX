# Metadata file I/O: findings

Why edited metadata comes back stale after a forced rescan, how the scanner
prioritizes metadata sources, and where reading/writing diverge from the
MetronInfo and ComicInfo specs. Written 2026-10-29.

Sections 1–4 describe the code **before** the format rework (`main` @
`34fc5bd`). Section 5 describes what replaced it and what is still open.

Specs used (XSDs fetched from the official repos):

| Format     | Versions                         | Source                                                    |
| ---------- | -------------------------------- | --------------------------------------------------------- |
| MetronInfo | v1.0, v1.1, v1.2                 | github.com/Metron-Project/metroninfo `schema/` |
| ComicInfo  | v1.0, v2.0 (stable), v2.1 (draft) | github.com/anansi-project/comicinfo `schema/`, `drafts/` |

`docs/MetronInfo.schema.xml` in this repo is **v1.1**; v1.2 is current.

---

## 1. Do reading and writing share code?

**No.** Each direction has its own hand-written field mapping, and they have
drifted apart:

| Direction | MetronInfo                                   | ComicInfo                                  |
| --------- | -------------------------------------------- | ------------------------------------------ |
| Read      | `Metadata.Parser.parse_metroninfo_xml/1`     | `Metadata.Parser.parse_comicinfo_xml/1`    |
| Write     | `Metadata.Writer.MetronInfoXml.build/1`      | `Metadata.Writer.ComicInfoXml.build/1`     |

- The parsers return a loose map (`%{title:, series:, credits:, ...}`); the
  writers take an Ecto `Book` with preloads. There is no shared intermediate
  shape, so nothing guarantees `parse(build(book))` gives back what was written.
- The scanner then maps that loose map onto `Book` columns by hand in **three
  different places** (`create_book_from_meta`, `move_book_file`,
  `update_book_file_from_meta` in `scanner/scanner.ex`), each with a different
  field list.
- Container handling is also split: the parser reads zip via `:zip.extract`,
  the writer via `:zip.zip_open`; the parser only reads embedded XML from
  `.cbz`/`.epub` (not `.cbr`/`.cb7`), the writer only embeds into `.cbz`.

### ComicInfo read coverage is very thin

`parse_comicinfo_xml/1` reads only: Title, Series, Number, Volume, Year,
Publisher, PageCount, Summary, Notes, Web, AgeRating, LanguageISO, Genre, Tags,
StoryArc. The writer emits much more. **Not read back** (silently dropped):

Count, AlternateNumber, Month, Day, Writer, Penciller, Inker, Colorist,
Letterer, CoverArtist, Editor, Translator, Imprint, Format, Characters, Teams,
Locations, CommunityRating, GTIN, StoryArcNumber, AlternateSeries/Count,
SeriesGroup, Manga, BlackAndWhite, MainCharacterOrTeam, ScanInformation,
Review, Pages.

This only bites for files that carry ComicInfo **without** MetronInfo (i.e.
files tagged by other tools) — Stashix always writes MetronInfo alongside.

---

## 2. Scan priority (current behaviour)

`Scanner.parse_file_metadata/1` builds `metadata = Map.merge(parsed_filename, file_xml)`.
Highest wins:

1. **Sidecar** `<stem>.xml` next to the file (MetronInfo *or* ComicInfo,
   sniffed by root tag). Merged over everything embedded, field by field.
   External ids are unioned per source. (`Parser.parse_comicinfo/1`)
2. **Embedded `MetronInfo.xml`** (`.cbz`/`.epub` only). Overrides ComicInfo
   field by field. If present, ComicInfo's `Title` is discarded.
3. **Embedded `ComicInfo.xml`** (`.cbz`/`.epub` only).
   - `.pdf`: the PDF info dict (`pdfinfo`: Title, Pages, CreationDate year)
     takes the place of 2–3.
   - `.cbr`/`.cb7`: nothing embedded is read; only the sidecar.
4. **Filename** (`Parser.parse_filename/1`) — lowest, **except**
   `issue_number`, where the filename *wins* over the file
   (`Map.get(parsed, :issue_number) || Map.get(comicinfo, :issue_number)`).
5. **Folder** — series name/years/ongoing always come from the parent folder
   (`find_or_create_series_cached/3`); `<Series>` in the file is never used to
   pick or rename the series, and folder values overwrite DB series edits.

How the result lands in the DB:

- A **non-forced** scan skips files whose mtime didn't change. After a
  write-back, `FileWriter.refresh_file_record/1` updates size/hash/mtime, so our
  own writes don't trigger a re-read.
- A **forced** scan re-reads every file and the **file wins** for:
  title, issue_number, volume, year (set to `nil`/filename when absent), and
  page_count, language, summary, community rating, cover/store date, notes,
  ISBN, UPC (DB value kept when absent).
- All child tables (genres, tags, arcs, stories, characters, teams, universes,
  locations, reprints, URLs, prices, external ids, credits) are **replaced**
  wholesale by `Importer.replace_book_metadata/2` — absent in file → wiped.
- Exception: if the book was matched (`metadata_matched_at`) and the file has
  **no** XML at all, the scan keeps DB metadata (`keep_fetched`).
- **Never** updated from the file on rescan (only on first create, or not at
  all): age_rating, publisher, imprint, collection_title, alternative_number,
  and every series-level field (format, sort name, start year, counts,
  alternative names). Edits to these in an external tagger are never picked up.

---

## 3. Why edits come back stale after a forced rescan

Each row is a way a DB edit is lost because the written file doesn't
round-trip through the reader + scanner.

| # | Field | Cause | Where | Status |
|---|---|---|---|---|
| 1 | Title | Writer emitted old `<Stories>`; reader takes first story as title. | `metron_info_xml.ex` `stories/1` | Fixed (`34fc5bd`) |
| 2 | Issue number | Scanner prefers the number parsed from the **filename** over the file's `<Number>`. | `scanner.ex` `update_book_file_from_meta` | Fixed |
| 3 | Year | MetronInfo has no Year; reader derives it from `CoverDate`/`StoreDate`. Editing only `year` (not the date) reverts. ComicInfo `<Year>` is also written from the date first. | `parser.ex` `parse_metroninfo_xml`, both writers | Fixed |
| 4 | Volume | Writer emits `series.volume \|\| book.volume` — a book-level edit is shadowed when the series has a volume. | `metron_info_xml.ex` `series/2` | Fixed |
| 5 | Language | Writer emits `series.language \|\| book.language` into `Series@lang`; reader sets book language from it. | `metron_info_xml.ex` `series/2` | Fixed |
| 6 | Series name / years | Series always rebuilt from the folder name; file and DB edits lose. | `scanner.ex` `find_or_create_series_cached` | Open (by design) |
| 7 | Anything (cbz) | A leftover `<stem>.xml` sidecar overrides freshly embedded XML. The cbz writer never removes it (it even *creates* one on the bad-zip fallback). | `parser.ex` `parse_comicinfo/1`, `file_writer.ex` | Fixed |
| 8 | Anything | Write-back is an async Oban job (`metadata_write`); a forced scan started before it runs re-reads the old file. Failed writes (e.g. `:ro` mount in `docker-compose.yml`) only log. | `metadata.ex` `enqueue_write/1` | Fixed |
| 9 | Story arcs (ComicInfo-only files) | Writer joins arcs with `", "`; reader stores the whole string as **one** arc. | `comic_info_xml.ex`, `parser.ex` | Fixed |
| 10 | Age rating `teen_plus` | ComicInfo has no Teen+ value; writer maps it to `Teen`. Reader maps the non-spec `"Teen+"`. Lossy for ComicInfo-only files. | both | Fixed |

---

## 4. Spec compliance gaps

### MetronInfo (writer targets v1.1, current is v1.2)

- **v1.2 additions not written or read:** `Series/EndYear`, `Series/Status`
  (`Cancelled|Completed|Hiatus|Ongoing`), `Series/Summary`. We have
  `series.end_year`, `series.ongoing`, `series.summary` in the DB.
- **`MangaVolume`** (all versions): not read or written.
- **`Publisher@id`, `Imprint@id`, `Creator@id`, `Role@id`**: not written;
  `Creator@id` is read but discarded.
- **Roles:** the DB enum has values outside `roleValues` (`General Manager`,
  `Production Manager`, `Brand Manager`, `VP of …`) and spells
  `Editor in Chief` where the schema has `Editor In Chief`. These produce
  schema-invalid files; they should be written as `Other`.
- **`ID@source`:** `:Unknown` would be written as `source="Unknown"`, which is
  not in `informationSource`.
- **`Series` is required** — ok (falls back to book title).
- `xs:all` → element order is free; ours is fine.
- **Language:** v1.0/1.1 restrict `lang` to two lowercase letters; v1.2 allows
  BCP 47 (`pt-BR`). We should write the BCP 47 tag only when targeting v1.2.
- `AgeRating` default is `Unknown`; we omit it for `:unknown` (valid).

### ComicInfo

- **Element order:** ComicInfo uses `xs:sequence`, so order matters to strict
  validators. Our writer puts `StoryArc` right after `AlternateNumber` and
  `CommunityRating` before `AgeRating`; both are out of sequence.
- **Version mixing:** the writer emits v2.1-draft-only elements (`Translator`,
  `Tags`, `GTIN`) next to v2.0 elements (`Day`, `Characters`, `AgeRating`, …),
  without declaring a version. Strict v2.0
  validators reject the draft elements.
- **Multi-value semantics:** creators/Genre/Tags/Characters/Teams/Locations/
  StoryArc/SeriesGroup are comma-separated; `Web` is **space**-separated
  (spaces in URLs percent-encoded); `StoryArc` pairs index-wise with
  `StoryArcNumber` (v2.1).
- **CommunityRating:** v2.0 allows 2 fraction digits, v2.1 one. We write one —
  valid for both.
- **AgeRating:** enum has 15 values (`Everyone 10+`, `G`, `PG`, `M`, `MA15+`,
  `R18+`, `Early Childhood`, `Kids to Adults`, …). We read only 7 of them and
  read a non-spec `"Teen+"`.
- **Manga / BlackAndWhite / Pages:** not read or written. `Manga=YesAndRightToLeft`
  is the standard reading-direction hint.
- **Not written:** `AlternateSeries`, `AlternateCount`, `SeriesGroup`,
  `StoryArcNumber`, `MainCharacterOrTeam`, `ScanInformation`, `Review`.

---

## 5. Rework: one module per format, one shared shape

Reading and writing now go through the same module per format, over one
canonical map, so a value that is written reads back as itself.

| Module | Role |
| --- | --- |
| `Stashix.Metadata.Record` | The canonical map (keys documented in the moduledoc). `from_book/1` builds it from the DB, applying "book value first, series value as fallback" for volume and language. |
| `Stashix.Metadata.Format.MetronInfo` | `parse/1` reads v1.0–v1.2; `build/2` writes `version:` 1.0, 1.1 or 1.2 (default 1.2); `detect_version/1`. |
| `Stashix.Metadata.Format.ComicInfo` | `parse/1` reads v1.0, v2.0 and v2.1; `build/2` writes `version:` 1.0, 2.0 or 2.1 in schema sequence order; `detect_version/1`. |
| `Stashix.Metadata.Format.XML` | Shared builder, safe parser (no DTD/entities) and value helpers. |
| `Stashix.Metadata.Parser` | Container lookup and precedence only (sidecar → MetronInfo → ComicInfo/PDF), plus filename parsing. |
| `Stashix.Metadata.Writer.FileWriter` | `Record.from_book/1` → both builders → CBZ embed / sidecar. |

The old `Writer.MetronInfoXml`, `Writer.ComicInfoXml` and `Writer.XML` are gone.

### Behaviour changes

- **ComicInfo version is a setting** (`comicinfo_version`, Admin → Metadata),
  default **2.0**. Readers always accept every version.
- **MetronInfo is written as v1.2**: adds `Series/EndYear`, `Series/Status`
  (`Ongoing` from `series.ongoing`), `Series/Summary`, `MangaVolume`,
  `Creator@id`; `lang` keeps BCP 47 tags (`pt-BR`).
- **Schema coercion on write:** roles outside the enum become `Other`;
  `Cover Artist` → `Cover`, `Editor in Chief` → `Editor In Chief`; `ID@source`
  values not in the enum are dropped; at most one `primary` ID and URL; prices
  need a two-letter country; `EndYear` is dropped when it is before
  `StartYear` or the series is ongoing; Format only from the enum.
- **ComicInfo reading** now covers every element: creators → credits,
  Characters/Teams/Locations, Imprint, Count, AlternateNumber/Series/Count,
  Year+Month+Day → cover date, StoryArc paired with StoryArcNumber, GTIN
  (filed as ISBN or UPC by shape), CommunityRating, Manga, BlackAndWhite,
  SeriesGroup, MainCharacterOrTeam, ScanInformation, Review. All 15 AgeRating
  values map to a Stashix rating; Stashix ratings are written so they read back
  as themselves (`teen_plus` ↔ `M`).
- **ComicInfo writing:** `Web` space-separated (spaces percent-encoded);
  Month/Day only written when they belong to the written Year.
- **Year:** ComicInfo's `Year` beats the year MetronInfo derives from its
  dates (row 3).
- **Issue number:** the file's number beats the filename (row 2).
- **CBZ + existing sidecar:** the sidecar is rewritten alongside the embed
  (row 7). No sidecar is created when there was none.

### Verification

- `test/stashix/metadata/format_test.exs`: per-version round trips of every
  field, ComicInfo sequence order for all versions, version gating, enum
  coercion, age-rating mapping.
- Output of every version was validated once with `xmllint --schema` against
  the official XSDs (MetronInfo XSD 1.1 `xs:assert`s stripped, since xmllint
  only speaks XSD 1.0; those rules are enforced in `build/2`). The XSDs are not
  vendored, so this is not part of `mix test`.

### Follow-up fixes

- **Write-back race (row 8):** every scan (library, series, single file)
  first calls `Metadata.flush_pending_writes/1`. It claims the waiting
  `WriteFileWorker` jobs for the books in scope with a conditional update
  (so each job is written once, by the queue or by the scan), writes them
  synchronously, marks them completed (or back to available on failure), then
  waits up to a minute for writes the queue is already executing.
- **One scanner mapping:** `create_book_from_meta`, `move_book_file` and
  `update_book_file_from_meta` now share `book_attrs_from_meta/3`. A rescan
  refreshes age rating, collection title, alternative number, imprint and
  publisher too; fields the file doesn't mention keep their DB value. A new
  book may take its publisher from the filename/folder; a rescan only replaces
  it with a publisher the file itself states (co-publishers are kept when the
  file's is among them).
- **RAR / 7z:** `Stashix.Metadata.Container` reads embedded
  `ComicInfo.xml` / `MetronInfo.xml` from zip, RAR (`unrar lb` / `p`, also
  served by the Docker image's 7z shim) and 7z archives. The type is sniffed
  from magic bytes, so a `.cbr` that is really a zip is read as a zip.

- **Archive type by content everywhere:** `Stashix.Media.Archive` lists and
  reads zip/RAR/7z entries, choosing the tool from the file's magic bytes. Both
  the page reader (`Extractor`) and the metadata reader (`Container`) use it,
  so a zip named `.cbr` gets pages, a thumbnail and metadata. Metadata is only
  embedded into a `.cbz` that really is a zip; anything else gets a sidecar.
- **ComicInfo `<Pages>`** is read into the record and, when a CBZ's
  ComicInfo.xml is rewritten, carried over from the existing one.
- **ComicInfo write-back off:** an existing ComicInfo.xml is left untouched
  (it used to be deleted, losing its Pages). Rewrites keep every entry's
  timestamp, and the reader ignores a ComicInfo.xml more than 60 s older than
  the MetronInfo.xml beside it, so the kept file can't bring back values
  edited since.

### Still open

1. **Series stays folder-authoritative** (row 6). `<Series>` and the series
   fields in the file are read into the record but the scanner ignores them.
2. **Writing into `.cbr`/`.cb7`** still goes to a sidecar (we can't rewrite
   RAR).
3. ComicInfo-only extras (Manga, BlackAndWhite, SeriesGroup, …) have no DB
   column, so they survive a read but not a DB → file write. `<Pages>` is the
   exception: it is carried over from the archive.
4. `docs/MetronInfo.schema.xml` is still v1.1; replace with v1.2.
