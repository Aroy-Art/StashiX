# Changelog

All notable changes to Stashix are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). Before 1.0.0 the database schema and
API can change between any two releases; back up the database before
upgrading.

## [Unreleased]

## [0.0.1] - unreleased

First public release.

### Added

- Self-hosted library server for comics and ebooks, with multiple libraries
  and folder watching.
- In-browser readers for CBZ, CBR, CB7 and PDF.
- Metadata from file names, ComicInfo.xml and MetronInfo.xml, plus matching
  against external metadata sources.
- Series, publisher (with aliases) and creator pages; full-text search.
- Admin and user roles with per-library access and age ratings.
- Light and dark themes; installable as a PWA.
- Prometheus metrics on a separate port.
- Docker image at `git.aroy-art.com/aroy/stashix`.

### Known issues

- The metrics listener (port 9568) has no authentication. It is not published
  by `docker-compose.yml`; set `:metrics_ip` to restrict it.
- `X-Forwarded-For` is trusted from any client, so the IP shown in the
  sessions list can be spoofed.
- Library files with many made-up XML element names can, over many scans,
  exhaust the atom table and crash the server.

[Unreleased]: https://git.aroy-art.com/aroy/stashix/compare/v0.0.1...HEAD
[0.0.1]: https://git.aroy-art.com/aroy/stashix/releases/tag/v0.0.1
