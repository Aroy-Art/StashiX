# Metadata Workflow

This document traces the full lifecycle of a metadata fetch — from the source
plugin API call through to the final write into the book's file on disk.

## Overview

```
Oban job
  └─ Stashix.Metadata.identify_book/1
       └─ Matcher.match_book/2
            ├─ (known external ID) ──────────────────────────┐
            └─ Sources.enabled/0                             │
                 └─ for each source, by priority:            │
                      search_series → score                  │
                      search_issues → score                  │
                      confident? → {:matched, source, cand}  │
                      else       → {:review, …}              │
                                                             ▼
                                               Apply.apply_book/5
                                                    │
                                                    ├─ Importer.replace_book_metadata/3  (DB)
                                                    ├─ Importer.upsert_external_ids/4    (DB)
                                                    └─ WriteFileWorker (Oban)
                                                              └─ FileWriter.write_book/2
```

---

## 1. Source Plugins

A source plugin is any module that implements `Stashix.Metadata.Source` and is
listed in `config :stashix, :metadata_sources`.

```elixir
# config/config.exs
config :stashix, :metadata_sources, [
  Stashix.Metadata.Sources.Metron,
  Stashix.Metadata.Sources.ComicVine,
  Stashix.Metadata.Sources.GCD
]
```

Each plugin implements:

| Callback | Purpose |
|---|---|
| `key/0` | Stable DB identifier, e.g. `"comic_vine"` |
| `config_schema/0` | Admin form fields (`:secret` / `:cookies` values are encrypted) |
| `req_options/1` | Base `Req` options: `base_url`, `auth`, headers |
| `default_rate_limit/0` | `{requests, per_ms}` fallback |
| `search_series/2` | Returns `[%Candidate{kind: :series}]` |
| `search_issues/2` | Returns `[%Candidate{kind: :issue}]` |
| `fetch_issue/2` | Returns a metadata map (see §5) |
| `fetch_series/2` | Returns a series map (see §5) |
| `cacheable?/1` _(optional)_ | Return `false` to skip caching an error wrapped in a 200 response |

`Stashix.Metadata.Sources` maintains one `metadata_sources` DB row per plugin
(created on demand, disabled by default). The row stores priority, the
per-source rate-limit override, and the encrypted config map.

A source must pass a connection test (`test_source/1`) before it can be
enabled. Changing any config field clears the test status and disables the
source until it is retested.

---

## 2. HTTP Context and Req Pipeline

`Stashix.Metadata.HTTP.context/2` builds the runtime context handed to every
source callback:

```elixir
%{
  config: %{"api_key" => "…"},   # decrypted
  req: %Req.Request{…},          # ready to call
  source_key: "comic_vine"
}
```

The `Req` client is built from the source's `req_options/1` and augmented with
two custom Req steps:

- **`metadata_cache`** — request step checks the cache (keyed by source + URL)
  before hitting the network; response step stores the body on a 2xx that
  passes `cacheable?/1`. Pass `cache: :short` for search results or
  `cache: :long` for detail records. TTLs come from `Settings.metadata/0`
  (`cache_search_hours`, `cache_detail_days`). Pass `refresh: true` to skip
  reads while still writing fresh results.

- **`rate_limit`** — blocks until a token is available from
  `Stashix.Metadata.RateLimiter`. The limit is either the admin override stored
  on `SourceConfig` or the source's `default_rate_limit/0`.

---

## 3. Matching

`Stashix.Metadata.Matcher` finds the best candidate for a book or series.

### Book match flow

```
known external id for this source?
  yes → Candidate{id: known_id, score: 1.0}
  no  → search_series(name, year, publisher) → score each series
        ├── confident series? → search top-1 only
        └── else              → search top-3 series
              search_issues(series_id, number, year) for each
              → score each issue
```

### Scoring

Issue score (0–1):

| Component | Weight |
|---|---|
| Series name similarity (Jaro, 0.95 cap) | 50 % |
| Issue number exact match | 30 % |
| Year proximity (±0/1/2 yr → 1.0/0.7/0.3) | 15 % |
| Publisher similarity | 5 % |

Series score (0–1): name 70 %, year 20 %, publisher 10 %.

Name comparison is normalised: lowercased, `&` → `and`, leading "the " and
trailing `(YYYY)` stripped, all non-alphanumeric collapsed to spaces.

### Confidence and auto_apply

`confident?/2` returns `true` when:

1. Top candidate score ≥ `auto_match_threshold` (default **0.9**)
2. Lead over runner-up ≥ `auto_match_margin` (default **0.1**)

A confident match is auto-applied only if the source's `auto_apply` flag is
set. Otherwise candidates go to a `MatchReview` for manual selection.

### Match review

When no source produces a confident match, `Stashix.Metadata` creates (or
updates) a `metadata_match_reviews` row with status `pending`, the search
query, and the scored candidates. Admins pick one from the Identify dialog;
resolving the review calls `apply_issue_metadata/5` directly.

---

## 4. Oban Jobs

Matching is driven by three Oban workers in the `:metadata` queue:

| Worker | Triggered by |
|---|---|
| `MatchBookWorker` | Single book enqueue, or fan-out from series/library worker |
| `MatchSeriesWorker` | Series page in admin; also enqueues a `MatchBookWorker` per book |
| `MatchLibraryWorker` | Full library re-scan from admin |

Rate-limited responses (`{:rate_limited, ms}`) snooze the job rather than
failing it. Jobs are deduplicated by `book_id` / `series_id` across
`available`, `scheduled`, `executing`, and `retryable` states.

---

## 5. Metadata Maps

`fetch_issue/2` returns an atom-keyed map. Required keys:

| Key | Type | Notes |
|---|---|---|
| `:series` | `String.t()` | Series name |
| `:issue_number` | `Decimal.t() \| nil` | Normalised numeric string |
| `:external_ids` | `[%{source:, source_id:, is_primary:}]` | Source attribution |

Optional keys (all `nil`-safe):

`:title`, `:cover_date`, `:store_date`, `:year`, `:summary`, `:language`,
`:cover_url`, `:credits` (`[%{creator:, creator_id:, roles: [String.t()]}]`),
`:characters`, `:teams`, `:locations`, `:arcs`, `:stories`, `:urls`,
`:series_external_ids`, `:series_sort_name`, `:series_format`,
`:series_start_year`, `:volume`.

`fetch_series/2` returns: `:name`, `:start_year`, `:end_year`, `:issue_count`,
`:summary`, `:publisher`, `:language`, `:format`, `:external_ids`.

These shapes mirror what `Stashix.Metadata.Parser` produces from a
`MetronInfo.xml`, so a source payload and a parsed file are interchangeable in
the apply layer.

---

## 6. Applying Metadata

`Stashix.Metadata.Apply.apply_book/5` writes source data onto a `Book`.

### Overwrite modes

Controlled by `Settings.metadata()["overwrite_mode"]`:

- **`"fill"`** (default) — only writes a field when the book's current value is
  `nil`, `""`, `[]`, or `:unknown`. A title that matches the book's filename
  stem counts as empty.
- **`"replace"`** — every field the source provides overwrites the local value.
- **`fields: [...]`** option (manual Identify dialog) — explicit list of keys
  to write; overrides the mode for those fields.

Issue number and page count are never overwritten in fill/replace mode — only
via an explicit `fields:` list — because a scanned value from the file is
considered authoritative.

External IDs are always **merged** (upserted per source), never replaced.

### Side effects

After updating the book:

- `apply_series_from_issue/2` fills any empty series fields (sort name, format,
  start year, volume) from the issue payload — in fill mode, never rename.
- `Importer.upsert_external_ids/4` upserts source IDs on the series too.
- `resolve_reviews/1` marks any pending `MatchReview` for this book as
  `resolved`.
- A `WriteFileWorker` job is enqueued when `write_to_files` is enabled.

---

## 7. Importer (DB Writes)

`Stashix.Metadata.Importer.replace_book_metadata/3` runs inside a transaction.
For each child table (genres, tags, arcs, stories, characters, teams,
universes, locations, reprints, URLs, prices, credits) it:

1. Deletes all existing rows for `book_id`.
2. Bulk-inserts the new rows with `Repo.insert_all`.

`only_present: true` (used by `Apply`) skips tables whose key is absent from
the metadata map, so a source that only provides credits does not clear genres.

Credits resolve creator names via `find_or_create_creator/1` (insert-or-select,
race-safe). Unknown role strings fall back to `:Other` rather than raising.

---

## 8. Writing to Files

`Stashix.Metadata.Writer.FileWriter` serialises the book's DB state back to
disk.

### CBZ

1. Opens the archive in-memory via `:zip.zip_open/2`.
2. Extracts all entries **except** `MetronInfo.xml` / `ComicInfo.xml` to a
   temp directory (zip-slip paths are rejected).
3. Writes the new `MetronInfo.xml` (always) and optionally `ComicInfo.xml`
   (when `write_comicinfo` is set).
4. Re-zips to a `.stashix-tmp` file, verifies entry count, copies permissions,
   then renames over the original (atomic on POSIX).
5. Image formats (jpg, png, webp, etc.) are stored uncompressed.

### Other formats (CBR, CB7, PDF, EPUB)

A `MetronInfo.xml` sidecar is written alongside the file:
`<book-basename>.xml`. EPUBs are not rewritten because their zip layout
(mimetype-first, stored) is strict.

### Scanner suppression

`Scanner.FileWatcher.suppress/1` is called before writing so the file-system
watcher does not treat the write as a user change and trigger a re-scan.
After a successful write, the `BookFile` row's hash, size, and mtime are
refreshed to match the new file state.

---

## Adding a New Source

1. Create `lib/stashix/metadata/sources/my_source.ex` implementing
   `Stashix.Metadata.Source`.
2. Add the module to `config :stashix, :metadata_sources` in `config.exs`.
3. Import `Stashix.Metadata.Sources.Helpers` for shared helpers (`blank?`,
   `strip_html`, `date`, `int`, `put`, `resources`, etc.).
4. Return `{requests, per_ms}` from `default_rate_limit/0`. Start
   conservative; the admin can override it per-installation.
5. Implement `cacheable?/1` if the API wraps errors in 200 responses.
6. Return `{:error, {:rate_limited, ms}}` when the source signals throttling,
   so the Oban job snoozes instead of consuming retries.
