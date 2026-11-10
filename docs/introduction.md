# Introduction

Stashix is a self-hosted comic book and ebook library server built with
Elixir, Phoenix LiveView and PostgreSQL.

These are the developer docs: module reference and notes on how the code
works. To install, configure or run Stashix, see the project site:

- [stashix.net](https://stashix.net/): overview and features
- [Installation](https://stashix.net/docs/get-started/installation/)
- [Configuration reference](https://stashix.net/docs/reference/configuration/)
- [Admin guide](https://stashix.net/docs/admin-guide/): scanner, library layout, monitoring

## Code map

| Area | Modules |
| ---- | ------- |
| Library: books, series, publishers, access | `Stashix.Library` |
| Scanning, parsing, folder watching | `Stashix.Scanner` |
| Metadata files and external sources | `Stashix.Metadata` |
| Users, sessions, roles | `Stashix.Accounts`, `Stashix.Auth.*` |
| Encrypted settings | `Stashix.Settings`, `Stashix.Vault` |
| Archive extraction, thumbnails | `Stashix.Media.*` |
| Web UI | `StashixWeb` (LiveViews under `StashixWeb.*Live`) |
| REST API | `StashixWeb.API.*` |

## Guides

- [Metadata: Source → File Workflow](metadata-workflow.html): how a match
  from an external source ends up in the database and in the file.
- [Metrics](metrics.html): config and code behind the Prometheus endpoint.
