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
