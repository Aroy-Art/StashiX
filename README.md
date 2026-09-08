# Stashix

Self-hosted comic book and ebook library server. Built with Elixir/Phoenix LiveView.

## Features

- Multiple library support (multiple root folders)
- Admin + user roles with per-library permissions and age-gate controls
- Full-text search backed by PostgreSQL tsvector
- Folder watching — auto-import new files
- In-browser readers for CBZ, CBR, CB7, PDF
- Metadata parsed from filenames, ComicInfo.xml, MetronInfo.xml
- Blurhash cover placeholders with WebP serving and on-demand resizing
- Publisher support with alias system
- PWA — installable on Android

## Stack

- **Backend:** Elixir, Phoenix LiveView, Ecto
- **DB:** PostgreSQL
- **Assets:** Tailwind v4, ESBuild, Heroicons, Lucide.dev

## Quick Start

```bash
cp .env.example .env
# edit .env — set POSTGRES_PASSWORD, SECRET_KEY_BASE, JWT_SECRET, LIBRARY_PATH
docker compose up -d
```

Access at `http://localhost:4000`. A setup wizard runs on first launch.

Generate `SECRET_KEY_BASE` with:

```bash
docker compose run --rm phoenix ./bin/stashix eval "IO.puts(:crypto.strong_rand_bytes(48) |> Base.encode64())"
```

## Development

```bash
cd stashix_web
mix setup        # install deps + create/migrate DB
mix phx.server   # http://localhost:4000
```

Requires Elixir 1.18+, Erlang/OTP 27+, PostgreSQL, and system deps: `vips`, `p7zip`, `unrar`, `pdfinfo`, `pdftoppm`.

## Configuration

| Env var           | Default (dev)                          | Purpose                                     |
| ----------------- | -------------------------------------- | ------------------------------------------- |
| `DATABASE_URL`    | _dev.exs default_                      | Ecto DB URL (`ecto://user:pass@host/db`)    |
| `SECRET_KEY_BASE` | _required in prod_                     | Phoenix cookie/session encryption           |
| `JWT_SECRET`      | `dev-secret-change-in-production`      | Guardian JWT signing secret                 |
| `PHX_HOST`        | `localhost`                            | Public hostname (used in URLs)              |
| `PORT`            | `4000`                                 | HTTP port                                   |
| `LIBRARY_PATH`    | `/libraries`                           | Root path where book files are scanned from |
| `DATA_DIR`        | `/tmp/stashix`                         | General app data                            |
| `THUMBNAIL_DIR`   | `<repo>/tmp/data/thumbnails`           | Extracted cover images                      |
| `IMAGE_CACHE_DIR` | `<repo>/tmp/data/cache/images/resized` | Resized/WebP cover cache                    |

`THUMBNAIL_DIR` and `IMAGE_CACHE_DIR` are created automatically. In production point them at a persistent volume — covers are re-extracted on scan if missing.

---

## TODO

### Metadata

- [ ] External metadata scraping (ComicVine, MangaUpdates, Open Library, AniList)
- [ ] Bulk metadata edit / match
- [ ] Cover art fetching from external sources

### Formats

- [ ] MOBI / AZW3 reader
- [ ] CBT (tar-based) support
- [ ] Webtoon / long-strip reader mode

### Users & Auth

- [ ] OAuth2 / SSO (Google, GitHub)
- [ ] Invite links
- [ ] User self-registration with admin approval
- [ ] Reading lists / shelves per user

### Library

- [ ] Duplicate detection
- [ ] Missing issue detection (series gap analysis)
- [ ] Smart collections (saved dynamic filters)
- [ ] Import from Kavita / Komga / Calibre

### Infrastructure

- [ ] S3 / object storage backend
- [ ] Metrics endpoint (Prometheus)
- [ ] OPDS catalog support
- [ ] Webhook notifications (Discord, Slack)
