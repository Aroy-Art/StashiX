# Auth and permission audit

Date: 2026-10-01. Scope: router, plugs, controllers, LiveViews, channels,
`Stashix.Library` access scoping, auth config. Read-through of the code; no
dynamic testing.

Status: findings 1–6 and the Low items fixed, except the metrics listener.

## High

### 1. JWT secret always the public default in Docker deploys — fixed

- `config/runtime.exs` fell back to `"dev-secret-change-in-production"` in
  prod instead of raising.
- `docker-compose.yml` never passed `JWT_SECRET` into the container and
  `.env.example` did not list it, so setting it in `.env` had no effect.
- Anyone who knows a user's UUID could forge a token for that user, admins
  included.
- The vault key is derived from the same secret, so stored metadata source
  credentials were decryptable by anyone with database access.
- `SECRET_KEY_BASE` also had a public default in `docker-compose.yml`.

Fix: prod raises when `JWT_SECRET` is unset; compose requires `JWT_SECRET` and
`SECRET_KEY_BASE` and passes `STASHIX_ENCRYPTION_KEY` through; `.env.example`
and README updated.

Upgrade note: on an existing deployment the vault key changes together with
`JWT_SECRET` (unless `STASHIX_ENCRYPTION_KEY` was already set), so stored
metadata source credentials can no longer be decrypted and must be entered
again. All existing logins are invalidated.

### 2. Logout did not log out — fixed

`SessionController.delete` removed only `guardian_default_token`. The refresh
token stayed in the cookie, and `Live.Hooks` and `Plugs.MediaAuth` fall back to
it, so the user was silently signed in again for up to 7 days.

Fix: the whole session is dropped.

## Medium

### 3. Refresh token accepted as access token — fixed

`TokenHelper.resource_from_token/1`, `Auth.Pipeline` and `UserSocket` verified
tokens without checking `typ`, so a 7-day refresh token worked as a Bearer and
socket token, defeating the 15-minute access TTL.

Fix: all three require `typ: "access"`.

### 4. No token revocation — fixed

Changing a password or role did not invalidate existing tokens (stateless JWT,
no session version). Deleted users were rejected correctly.

Fix: `users.token_version` is embedded in every token as `ver` and bumped when
the password or role changes; tokens with another version are rejected. Tokens
issued before this change carry no `ver`, so everyone signs in again once.

### 5. Last admin can be deleted through the API, which reopens setup — fixed

`AdminUserController.delete` had no self or last-admin guard (the admin
LiveView guards self-delete), and `update` could demote the last admin. With
zero users `Accounts.setup_complete?/0` is false and an unauthenticated
`POST /api/setup` creates a new admin.

Fix: `Accounts.delete_user/1` and `update_user/2` refuse to delete or demote
the last admin.

### 6. No login rate limiting — fixed

`POST /api/auth/login`, `POST /login` and the `LoginLive` `"login"` event
allowed unlimited password guessing.

Fix: `Stashix.Auth.LoginThrottle` refuses a login name after 10 failed attempts
within 5 minutes; all three entry points go through it via
`Accounts.authenticate_user/2`. It is keyed by login name, not client address,
so someone can lock a known account out for up to 5 minutes at a time, and
guessing one password across many accounts is not limited. State is in memory,
per node.

## Low

- Scan tasks — fixed: `TaskController.index` returned tasks for all libraries
  to any user. Now filtered to libraries the user can read.
- `root_path` — fixed: the server filesystem path was returned to non-admins by
  `LibraryController.index` and `show`. Now admins only.
- Stale permissions on live sockets — fixed: `access` and role are assigned at
  mount only, so a revoked user kept access until the socket reconnected. Login
  now stores a `live_socket_id`, and a password, role or library permission
  change, or deleting the user, disconnects that user's LiveView sockets so
  they mount again. Sessions created before this change have no
  `live_socket_id` and are not disconnected until the next login.
- Series folder cover — fixed: `Library.get_series_cover/2` served the folder
  cover without an age rating check. It is now served only to users who can see
  every book in the series; others get the cover of a book they can see.
- Metrics listener on `0.0.0.0:9568` is unauthenticated — open, left as is. It
  is documented and not published in `docker-compose.yml`; binding it to
  localhost by default would stop a Prometheus container from scraping it. Set
  `:metrics_ip` to restrict it.
- Atom exhaustion — fixed: `String.to_atom(params["sort"])` in
  `BookController.index` was reachable by any authenticated user. The sort is
  now passed as a string, which also makes the `sort` parameter work (the atom
  never matched). `AdminLive` no longer converts the role to an atom either.
- `Plugs.RequireAuth` was unused — removed.

## Checked, no issue found

- Every LiveView mounts with `:require_auth` or `:require_admin`; login and
  setup are intentionally open.
- Admin API routes sit behind `RequireAdmin`; admin events in the book and
  series LiveViews are guarded; the identify component renders only for admins.
- All `Library` read queries go through `Access.books/1` or `Access.series/1`;
  a missing `:access` option raises instead of leaking.
- Media routes (cover, page) are cookie-authenticated and access-scoped.
- The metadata image proxy is host-allowlisted.
- Channel join checks the user id; progress updates are access-checked.
- Setup endpoints refuse once a user exists.

# Input handling and deployment audit

Date: 2026-10-14. Scope: what the first audit did not cover — parsing of
library files (ComicInfo/MetronInfo XML, archives), client-side JS, the image
proxy, cover and page serving, Docker setup and dependencies — plus the admin
events added since 2026-10-01. Read-through of the code, with `mix hex.audit`
and a local check of XML entity handling.

Threat model: anyone who can put a file into a library controls its embedded
metadata, so everything parsed from library files is untrusted.

Status: findings 1–4 fixed; the Low items are open.

## High

### 1. Stored XSS in the publisher picker — fixed

The `PublisherSearch` hook (`assets/js/app.js`) built its badges and dropdown
with template strings assigned to `innerHTML`, interpolating publisher names
unescaped. Publisher names come from the `<Publisher>` element of files in a
library or from metadata sources. A file with a crafted publisher name ran
script in an admin's browser when they opened the Edit dialog of a book or
series, with the admin's LiveView session (create users, change roles).

Fix: every interpolated value (name and id) goes through `escapeHTML`.

## Medium

### 2. Book links were stored with any scheme — fixed

ComicInfo `<Web>` links were limited to http(s), but MetronInfo `<URLs>` and
links from metadata sources were stored as is. `<.link>` refuses a
`javascript:` destination, so this was not XSS, but the book page crashed for
everyone. The Identify dialog rendered source links with a plain `<a>`, which
does not check the scheme.

Fix: the parser keeps only http(s) MetronInfo links, and
`Importer.web_url?/1` filters links in both write paths (`replace` and
`merge_urls`). The Identify dialog only links candidates that pass it.

### 3. `stashix_web/docker-compose.yml` had hardcoded secrets — fixed

A leftover compose file set `JWT_SECRET: "changeme-jwt-secret"`, a fixed
`SECRET_KEY_BASE` and Postgres password `changeme`, and published Postgres on
host port 5434. Anyone deploying with it was back at finding 1 of the first
audit.

Fix: secrets are required from the environment (`${VAR:?}`) and Postgres is
published on `127.0.0.1` only. The root `docker-compose.yml` remains the
documented one; this file could be removed.

### 4. Untrusted XML parsed with DTDs enabled — fixed

`Parser` called SweetXml `parse/1`, whose default is `dtd: :all`. On the OTP in
use (29, pinned by the Docker image) xmerl refuses entities by default
(`:entities_not_allowed`), so XXE was not exploitable, but that rested on the
OTP default.

Fix: both XML parse calls pass `dtd: :none`. Tests cover an external entity
pointing at a local file.

Still open: xmerl turns element names into atoms, so files with many distinct
made-up element names can fill the atom table over many scans (a VM crash, not
a data leak). Fixing it means replacing xmerl with a parser that keeps names as
binaries (e.g. Saxy).

## Low — open

- Dependency advisories from `mix hex.audit`: cloak 1.1.4
  (EEF-CVE-2026-95105, AES-CTR), cloak_ecto 1.3.0 (EEF-CVE-2026-94206, PBKDF2
  field), decimal 3.1.1 (EEF-CVE-2026-97853, `Decimal.round/3` places). None
  is reachable as used (AES-GCM cipher, no PBKDF2 fields, `round/1` only).
  decimal is bumped to 3.2.0. cloak and cloak_ecto have no fixed release
  (2026-10-29), so `mix hex.audit` keeps reporting them; accepted for now.
  Stashix only uses `Cloak.Ciphers.AES.GCM` (`config/runtime.exs`) and one
  `Cloak.Ecto.Map` field (`Stashix.Encrypted.Map`). Revisit if either changes:
  an AES-CTR cipher or a `Cloak.Ecto.PBKDF2` field would make them reachable.
- Option injection into 7z/unrar: `Extractor` and the `unrar` shim in the
  Dockerfile pass archive entry names as arguments. A name starting with `-`
  is read as a switch. Pass `--` before file names.
- `Plug.RewriteOn [:x_forwarded_for]` trusts the header from any client, so
  the IP shown in the sessions list can be spoofed. Login throttling is keyed
  by login name and is unaffected. Rewrite only behind a trusted proxy.
- Session cookie has no `secure: true`; no `force_ssl`/HSTS and no CSP.
  Acceptable behind a TLS-terminating proxy.
- Book and series covers are access-checked but sent with
  `cache-control: public`, so a shared cache could hand an age-restricted cover
  to another user. Use `private`, as pages do.
- The container runs as root (no `USER` in the Dockerfile). The library mount
  is read-only.
- Refresh tokens are not single-use: refreshing issues a new one, the old one
  stays valid until expiry. Revoking the session ends both.
- `inspect(reason)` in `BookController.pages/page` and `AuthController`
  returns tool stderr and server paths to the client.

## Checked, no issue found

- Admin events added since the first audit (series push publishers / age
  rating) are in `@admin_events`.
- `Accounts.revoke_session/2` only touches the caller's sessions.
- The image proxy re-checks scheme and host on every redirect and allowlists
  content types.
- The zip-slip guard in `FileWriter` rejects unsafe entry paths.
- CORS `*` is sent with credentials, which browsers refuse for credentialed
  reads, so cookie-authenticated media is not readable cross-origin.
- Covers are always stored as `.jpg`; nothing from an archive is served as
  HTML or SVG.
- No `raw`/`{:safe, …}` on user data, no SQL built by interpolation, no
  `String.to_atom` on request input.
