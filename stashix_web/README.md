# Stashix

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Configuration

All paths can be overridden with environment variables. Defaults are designed for local development.

| Env var | Default | Purpose |
|---|---|---|
| `DATA_DIR` | `/tmp/stashix` | General app data |
| `THUMBNAIL_DIR` | `<repo>/tmp/data/thumbnails` | Full-size cover images extracted from books |
| `IMAGE_CACHE_DIR` | `<repo>/tmp/data/cache/images/resized` | Resized/WebP variants cached on first request |
| `LIBRARY_PATH` | `/libraries` | Root path where book files are scanned from |
| `JWT_SECRET` | `dev-secret-change-in-production` | Secret for signing auth tokens |

### Data directories

On first scan, Stashix extracts a cover image from each book and writes it to `THUMBNAIL_DIR`. When a cover is requested with a `?w=` parameter, a resized copy is generated and cached in `IMAGE_CACHE_DIR` — subsequent requests for the same size are served from cache.

Both directories are created automatically. In development they live under `tmp/` in the repo root (gitignored). In production set the env vars to a persistent volume path, otherwise covers are lost on restart.

After changing `THUMBNAIL_DIR`, re-scan your libraries to regenerate covers at the new location.

### Auth sessions

Access tokens expire after 15 minutes. A refresh token (7-day TTL) is stored alongside in the session cookie and used to silently issue a new access token — the user is only prompted to log in again if the refresh token expires or is invalid.
