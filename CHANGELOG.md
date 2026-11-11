# Changelog

All notable changes to Stashix are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). Before 1.0.0 the database schema and
API can change between any two releases; back up the database before
upgrading.

## [Unreleased]

## [0.0.2] - 2026-11-11

Bug fixes, and metadata sidecars named after their format.

Metadata sidecars are now written as `<file>.MetronInfo.xml` and
`<file>.ComicInfo.xml`. An existing `<file>.xml` sidecar is still read, and is
replaced by the new files the next time Stashix writes that book's metadata.

### Added

- Disable match buttons when no source is ready ([`f6d6ebe`](https://github.com/aroy-art/stashix/commit/f6d6ebea7357b0bfb543eca1a170a939a32841d1)) by [@Aroy-Art](https://github.com/Aroy-Art)

### Fixed

- Centre the mobile page window on the current page ([`c98a859`](https://github.com/aroy-art/stashix/commit/c98a85927f32f74a4574055fb562aed33ea63e99)) by [@Aroy-Art](https://github.com/Aroy-Art)
- Allow loopback origins for the LiveView socket ([`04f0fda`](https://github.com/aroy-art/stashix/commit/04f0fdaec0e1b3c4a2fdbf13ccc24128d12bac7d)) by [@Aroy-Art](https://github.com/Aroy-Art)
- Install inotify-tools in the runtime image ([`1d6dbff`](https://github.com/aroy-art/stashix/commit/1d6dbff40c1a034cac8c05cc632f6bd1d44079b7)) by [@Aroy-Art](https://github.com/Aroy-Art)
- Keep running when the file watcher can't start ([`79b6cb3`](https://github.com/aroy-art/stashix/commit/79b6cb30923e6a37410aa3aac346495e1b09f266)) by [@Aroy-Art](https://github.com/Aroy-Art)
- Stop the initial-load cover from blocking clicks ([`684525f`](https://github.com/aroy-art/stashix/commit/684525fd2f14f737f313c3fb948570ea267566d1)) by [@Aroy-Art](https://github.com/Aroy-Art)
- Keep credits that come without a role ([`7a76339`](https://github.com/aroy-art/stashix/commit/7a763398b90086298c2cd1b66fc21b37249eb892)) by [@Aroy-Art](https://github.com/Aroy-Art)
- Serve digested favicon and manifest in prod ([`1311adb`](https://github.com/aroy-art/stashix/commit/1311adbeaf59f7cfd1f84911a3db308b0305598a)) by [@Aroy-Art](https://github.com/Aroy-Art)
- One access line per request ([`c002741`](https://github.com/aroy-art/stashix/commit/c0027412ad3eaeee78e4b432f273eb5452bcf201)) by [@Aroy-Art](https://github.com/Aroy-Art)
- Add lksctp-tools to silence the libsctp warning ([`0003573`](https://github.com/aroy-art/stashix/commit/0003573ca6e84fcf8d06a5707dc00ec90bc9aea3)) by [@Aroy-Art](https://github.com/Aroy-Art)
- Show blurhash behind series start-reading picks ([`97e400d`](https://github.com/aroy-art/stashix/commit/97e400d53d408152684a893a7bff1d096768c9f0)) by [@Aroy-Art](https://github.com/Aroy-Art)
- Blurhash placeholder for folder cover images ([`1620dbf`](https://github.com/aroy-art/stashix/commit/1620dbf566f03a7320443357659364357816820a)) by [@Aroy-Art](https://github.com/Aroy-Art)
- Name sidecars after their format ([`ecf73b1`](https://github.com/aroy-art/stashix/commit/ecf73b182a2d396dce71cf42914d0b2576c7df77)) by [@Aroy-Art](https://github.com/Aroy-Art)

### Known issues

- The metrics listener (port 9568) has no authentication. `docker-compose.yml`
  does not publish it; if you publish it, bind it to localhost or a private
  interface.
- `X-Forwarded-For` is trusted from any client, so the IP shown in the
  sessions list can be spoofed.
- Library files with many made-up XML element names can, over many scans,
  exhaust the atom table and crash the server.

## [0.0.1] - 2026-11-10

First public release.

### Added

- Self-hosted library server for comics and ebooks, with multiple libraries
  and folder watching.
- In-browser readers for CBZ, CBR, CB7, EPUB and PDF, with a webtoon
  (long-strip) mode. EPUB and PDF pages are shown as images.
- Metadata from file names, ComicInfo.xml and MetronInfo.xml, plus matching
  against ComicVine, Metron and the Grand Comics Database, with a
  library-wide match and review queue.
- Edited metadata written back to ComicInfo.xml / MetronInfo.xml in your
  files.
- Series, publisher (with aliases) and creator pages; full-text search.
- Admin and user roles with per-library access and age ratings.
- Library health checks for unreadable and unsupported files.
- Light and dark themes; installable as a PWA.
- Prometheus metrics on a separate port.
- Docker image at `ghcr.io/aroy-art/stashix`.

### Known issues

- The metrics listener (port 9568) has no authentication. `docker-compose.yml`
  does not publish it; if you publish it, bind it to localhost or a private
  interface.
- `X-Forwarded-For` is trusted from any client, so the IP shown in the
  sessions list can be spoofed.
- Library files with many made-up XML element names can, over many scans,
  exhaust the atom table and crash the server.

[Unreleased]: https://github.com/aroy-art/stashix/compare/v0.0.2...HEAD
[0.0.2]: https://github.com/aroy-art/stashix/releases/tag/v0.0.2
[0.0.1]: https://github.com/aroy-art/stashix/releases/tag/v0.0.1
