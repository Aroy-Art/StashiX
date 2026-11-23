<h1 align="center">
  <img src="docs/assets/logo.svg" alt="" height="72">
  <br>
  <img src="docs/assets/wordmark.svg" alt="Stashix" height="88">
</h1>

Self-hosted comic book and ebook library server. Built with Elixir/Phoenix LiveView.

Documentation: **[stashix.net](https://stashix.net/docs/)**: [installation](https://stashix.net/docs/get-started/installation/), [configuration](https://stashix.net/docs/reference/configuration/), [monitoring](https://stashix.net/docs/admin-guide/monitoring/).

> [!WARNING]
> **Stashix is early software.** Expect bugs, and back up your database before upgrading.
> [Here's how you can help](https://stashix.net/blog/post/how-to-help/).

## Features

- Multiple libraries, with admin and user roles, per-library access and age ratings
- In-browser readers for CBZ, CBR, CB7, EPUB and PDF, including a webtoon mode
- Metadata from filenames, ComicInfo.xml and MetronInfo.xml, plus matching against ComicVine, Metron and GCD
- Full-text search, folder watching, publisher aliases
- Installable as a PWA

See [stashix.net](https://stashix.net/docs/get-started/) for the full list.

## Quick Start

```bash
cp .env.example .env   # fill in the secrets and LIBRARIES_PATH
docker compose up -d
```

Open `http://localhost:4000` and follow the setup wizard. The
[installation guide](https://stashix.net/docs/get-started/installation/) covers
generating secrets, file permissions and troubleshooting.

> [!WARNING]
> Stashix is pre-1.0: the database schema can change between any two releases.
> Back up the database before every upgrade:
>
> ```bash
> docker compose exec db pg_dump -U stashix stashix > stashix-backup.sql
> ```
>
> See [Update Stashix](https://stashix.net/docs/get-started/installation/#update)
> for the full steps.

## Development

```bash
cd stashix_web
mix setup        # install deps + create/migrate DB
mix phx.server   # http://localhost:4000
```

Requires Elixir 1.18+, Erlang/OTP 27+, PostgreSQL, and system deps: `vips`, `p7zip`, `unrar`, `pdfinfo`, `pdftoppm`.

**Stack:** Elixir, Phoenix LiveView, Ecto, PostgreSQL; Tailwind v4, ESBuild, Heroicons, Lucide.

Defaults in development:

| Env var             | Default (dev)                          |
| ------------------- | -------------------------------------- |
| `DATABASE_URL`      | _dev.exs default_                      |
| `DATA_DIR`          | `/tmp/stashix`                         |
| `THUMBNAIL_DIR`     | `<repo>/tmp/data/thumbnails`           |
| `IMAGE_CACHE_DIR`   | `<repo>/tmp/data/cache/images/resized` |
| `PAGE_CACHE_DIR`    | `<repo>/tmp/data/cache/pages`          |
| `CALIBRE_CACHE_DIR` | `<repo>/tmp/data/cache/calibre`        |

All production settings are in the
[configuration reference](https://stashix.net/docs/reference/configuration/).
Developer notes live in [`docs/`](docs/) and in the HexDocs build (`mix docs`).

## Contributing

Bug reports, feature ideas, docs fixes and code are all welcome. Start with
[how you can help](https://stashix.net/blog/post/how-to-help/), and see the
[contributing guide](https://stashix.net/docs/contributing/) for details.
Commits must be signed off (`git commit -s`) under the
[Developer Certificate of Origin](https://developercertificate.org/).

### Translations

[![Translation status](https://hosted.weblate.org/widget/stashix/multi-auto.svg)](https://hosted.weblate.org/engage/stashix/)

Stashix is translated on [Hosted Weblate](https://hosted.weblate.org/engage/stashix/),
in the browser; no Git or Elixir needed.

1. Sign in to Hosted Weblate (an account there, or GitHub/GitLab login).
2. Open the [Stashix project](https://hosted.weblate.org/projects/stashix/), pick
   your language, or choose **Start new translation** to add one.
3. Translate. Keep placeholders such as `%{count}` and `%{name}` exactly as
   they are, and fill in every plural form.

Weblate commits translations to the `translations` branch, signed off in your
name under the DCO, and they reach `main` through a pull request. A new
language shows up in Stashix once enough of it is done. Spotted a mistake in
the English text itself? Leave a comment on the string in Weblate or open an
issue.

Code contributors: don't edit the translated `.po` files by hand, as that
clashes with Weblate. After adding or changing UI text, run
`mix gettext.extract --merge` in `stashix_web/` and commit the `.pot` and
`en` files.

## License

Stashix is licensed under the [GNU Affero General Public License v3.0 or later](LICENSE).

---

## TODO

### Metadata

- [x] External metadata scraping (ComicVine, Metron, GCD)
- [ ] More metadata sources (MangaUpdates, Open Library, AniList)
- [x] Bulk metadata match (library-wide match + review queue)
- [x] Write edited metadata back to files (ComicInfo.xml / MetronInfo.xml)
- [ ] Bulk metadata edit
- [ ] Cover art fetching from external sources
- [ ] Use ComicInfo `<Pages>`: `FrontCover` as the cover, skip `Deleted`/ad pages, `DoublePage` for spreads in the reader (today Pages is only preserved on write)
- [ ] Generate ComicInfo `<Pages>` (image size/dimensions, cover, spreads) when writing ComicInfo.xml

### Formats

- [ ] Text EPUB reader (EPUBs are read image-only today)
- [ ] Full PDF reader (text selection and search)
- [ ] MOBI / AZW3 reader
- [ ] CBT (tar-based) support
- [x] Webtoon / long-strip reader mode

### Users & Auth

- [ ] OAuth2 / SSO (Google, GitHub)
- [ ] Invite links
- [ ] User self-registration with admin approval
- [ ] Reading lists / shelves per user

### Library

- [x] Health checks (file integrity, unsupported files)
- [ ] Duplicate detection
- [ ] Missing issue detection (series gap analysis)
- [ ] Smart collections (saved dynamic filters)
- [ ] Import from Kavita / Komga / Calibre

### Infrastructure

- [ ] S3 / object storage backend
- [x] Metrics endpoint (Prometheus)
- [ ] OPDS catalog support
- [ ] Webhook notifications (Discord, Slack)

### Localization

- [ ] Translatable UI (all user-facing strings extracted)
- [ ] Translations into other languages
- [ ] Locale-aware dates and numbers
