# Release plan — 0.0.1

Goal: tag the first public release, with a versioned Docker image that the
root `docker-compose.yml` pulls instead of building from source.

**How to resume:** find the first unticked box. Paths are relative to the
repository root. Tick boxes in the commit that does the work.

Status legend: `[ ]` todo · `[x]` done · `[~]` started, see note · `[-]` dropped, see note

---

## Required

- [x] **1. Version.** `stashix_web/mix.exs` → `0.0.1`.
- [ ] **2. Tag.** Last step: `git tag -s v0.0.1` on the release commit, push the
  tag. Tags are `vX.Y.Z`.
- [x] **3. Versioned image.** `.forgejo/workflows/release.yaml` runs on `v*`
  tags, checks that the tag, `mix.exs` and the compose pin agree, then pushes
  `:X.Y.Z` and `:latest`. `build.yaml` still pushes `:dev` from main.
- [x] **4. Compose pulls the image.** Root `docker-compose.yml` uses
  `image: git.aroy-art.com/aroy/stashix:0.0.1`. The release commit bumps the
  pin together with `mix.exs` (the release workflow fails if they differ), so
  the tagged compose file always runs its own release. Renovate's
  docker-compose manager also picks the image up, as a backstop.
  - [ ] Confirm the registry package is public, otherwise `docker compose pull`
    needs a login.
- [x] **5. CHANGELOG.md.** Date the 0.0.1 entry in the release commit.
- [x] **6. Dependency advisories.** cloak 1.1.4 and cloak_ecto 1.3.0 are the
  latest releases; there is no fixed version to bump to. Neither advisory is
  reachable as used (AES-GCM cipher, no PBKDF2 fields). Accepted and noted in
  `docs/security-audit.md`; `mix hex.audit` keeps reporting them.
- [x] **6b. bandit 1.14.0** — EEF-CVE-2026-116078 (HIGH, HTTP/2 memory
  amplification), new on 2026-10-29. Updated to 1.14.1.
- [x] **7. 7z/unrar option injection.** `Extractor` passes `--` before file
  names; the Dockerfile's `unrar` shim (now `stashix_web/unrar.sh`) skips
  switches up to `--` and lists names with spaces correctly. Regression tests
  for dash-named entries in `extractor_test.exs`.
- [x] **8. Remove `stashix_web/docker-compose.yml`.**
- [x] **9. PDF in Docker.** The runtime image installs no `poppler-utils`, so
  `pdfinfo`/`pdftoppm` were missing and PDF books could not be read or
  counted. Added; checked `pdfinfo`/`pdftoppm` on a PDF in the built image,
  and the `unrar` shim and `7z --` on a dash-named entry.

## Quick wins

- [ ] **10.** Write `docs/introduction.md` (docs main page, currently a stub).
- [ ] **11.** README: refresh the TODO list (metadata sources exist); Elixir
  version (README 1.18+, `mix.exs` `~> 1.14`).
- [ ] **12.** Root compose: require `POSTGRES_PASSWORD` or drop it from the
  README's must-set list.
- [ ] **13.** README: pre-release note — back up the database before upgrading.

## Nice to have

- [ ] **14.** Align OTP: CI tests on 28.4, the image (`elixir:1.20-alpine`)
  runs 29.
- [ ] **15.** Drop the Go/`frontend/` entries from `.gitignore`.
- [ ] **16.** Commit or stash unrelated work in the tree before tagging.

## Release steps

1. Release commit: `mix.exs` version, compose pin, CHANGELOG date.
2. `git tag -s v0.0.1 && git push origin v0.0.1`.
3. Check the Release workflow pushed `:0.0.1` and `:latest`.
4. On a clean machine: `cp .env.example .env`, fill it in,
   `docker compose up -d`, run the setup wizard, scan a library.
5. Create the Forgejo release from the CHANGELOG entry.
