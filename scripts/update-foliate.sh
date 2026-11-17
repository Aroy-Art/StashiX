#!/bin/sh
# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Vendors foliate-js at commit $1 into stashix_web/priv/static/vendor/foliate/,
# replacing what is there. foliate-js has no releases, so it is pinned by
# commit. The text reader imports it at runtime, so it stays out of app.js.
#
# Only the modules the reader's View can load are copied: not the demo
# reader, OPDS, its own PDF.js wrapper (Stashix vendors PDF.js itself) or the
# zip reader (EPUB entries come from the server one at a time).
set -eu

if [ $# -ne 1 ]; then
  echo "usage: $0 <foliate-js commit>" >&2
  echo "latest: git ls-remote https://github.com/johnfactotum/foliate-js HEAD" >&2
  exit 1
fi

commit=$1
cd "$(git rev-parse --show-toplevel)"
dest=stashix_web/priv/static/vendor/foliate
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git -C "$tmp" init -q
git -C "$tmp" fetch -q --depth 1 https://github.com/johnfactotum/foliate-js "$commit"
git -C "$tmp" checkout -q FETCH_HEAD

rm -rf "$dest"
mkdir -p "$dest/vendor"
for f in view.js epub.js epubcfi.js progress.js overlayer.js text-walker.js paginator.js \
  fixed-layout.js search.js footnotes.js tts.js mobi.js fb2.js comic-book.js LICENSE; do
  cp "$tmp/$f" "$dest/"
done
# fflate inflates MOBI/AZW3 text records.
cp "$tmp/vendor/fflate.js" "$dest/vendor/"
echo "$commit" >"$dest/VERSION"

echo "foliate-js $commit vendored in $dest ($(du -sh "$dest" | cut -f1))"
