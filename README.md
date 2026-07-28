# Stashix

Self-hosted comic book and ebook library server. Built with Go + React.

## Features (MVP)

- Multiple library support (multiple root folders)
- Admin + User roles with per-library permissions and age-gate controls
- Full-text search backed by PostgreSQL tsvector
- Folder watching — auto-import new files
- In-browser readers for CBZ, CBR, CB7, EPUB, PDF
- Metadata parsed from filenames, ComicInfo.xml, MetronInfo.xml
- WebSocket-first real-time sync (REST API fallback)
- JWT authentication
- Docker + Caddy (auto-TLS)

## Stack

- **Backend:** Go, chi, pgx, sqlc, gorilla/websocket, fsnotify
- **Frontend:** React, Vite, TypeScript, Zustand
- **DB:** PostgreSQL
- **Proxy:** Nginx

## Quick Start

```bash
cp .env.example .env
# edit .env with your values
docker compose up -d
```

Access at `https://your-domain.com` (or `http://localhost` in dev).

## Development

```bash
docker compose -f docker-compose.dev.yml up -d
# backend
cd backend && DATABASE_URL="postgres://stashix:stashix@localhost:5432/stashix?sslmode=disable" JWT_SECRET="dev-secret-key" DATA_DIR="tmp/stashix/data" THUMBNAIL_DIR="tmp/stashix/thumbs" air
# frontend
cd frontend && npm install && npm run dev
```

---

## TODO (Post-MVP)

### Metadata

- [ ] External metadata scraping (ComicVine, MangaUpdates, Open Library, AniList)
- [ ] Manual metadata editing UI
- [ ] Bulk metadata edit / match
- [ ] Cover art fetching from external sources
- [ ] Series grouping and arc detection

### Formats

- [ ] MOBI / AZW3 reader
- [ ] CBT (tar-based) support
- [ ] WebtoonZ / long-strip reader mode

### Users & Auth

- [ ] OAuth2 / SSO (Google, GitHub)
- [ ] Invite links
- [ ] User self-registration with admin approval
- [ ] Reading lists / shelves per user
- [ ] Activity feed

### Reading Experience

- [ ] Mobile-optimized reader
- [ ] Double-page spread mode
- [ ] Reading direction setting (LTR / RTL / vertical)
- [ ] Bookmarks and annotations
- [ ] Offline / PWA support

### Library

- [ ] Duplicate detection
- [ ] Missing issue detection (series gap analysis)
- [ ] Smart collections (saved dynamic filters)
- [ ] Import from Kavita / Komga / Calibre

### Infrastructure

- [ ] S3 / object storage backend for files
- [ ] Redis for WS pub/sub (multi-instance scale-out)
- [ ] Metrics endpoint (Prometheus)
- [ ] OPDS catalog support
- [ ] Webhook notifications (Discord, Slack)
