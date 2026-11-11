#!/bin/sh
# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Drafts release $1 at the top of CHANGELOG.md from the commits since the last
# tag. Older releases are left exactly as they are. Run it before tagging,
# then edit the new entry by hand.
set -eu

if [ $# -ne 1 ]; then
  echo "usage: $0 vX.Y.Z" >&2
  echo "preview without writing: git cliff --unreleased" >&2
  exit 1
fi

tag=$1
cd "$(git rev-parse --show-toplevel)"

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "$tag is already tagged; its notes are in CHANGELOG.md" >&2
  exit 1
fi

if grep -q "^## \[${tag#v}\]" CHANGELOG.md; then
  echo "CHANGELOG.md already has an entry for ${tag#v}" >&2
  exit 1
fi

git cliff --unreleased --tag "$tag" --prepend CHANGELOG.md

# Reference links at the bottom: [Unreleased] now compares from this tag, and
# this version links to its release (the project site's release notes link).
repo=https://github.com/aroy-art/stashix
tmp=$(mktemp)
awk -v tag="$tag" -v ver="${tag#v}" -v repo="$repo" '
  /^\[Unreleased\]: / {
    print "[Unreleased]: " repo "/compare/" tag "...HEAD"
    print "[" ver "]: " repo "/releases/tag/" tag
    next
  }
  { print }
' CHANGELOG.md >"$tmp"
mv "$tmp" CHANGELOG.md
