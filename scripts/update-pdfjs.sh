#!/bin/sh
# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Vendors PDF.js $1 (an npm version of pdfjs-dist, e.g. 6.5.438) into
# stashix_web/priv/static/vendor/pdfjs/, replacing what is there. The text
# reader imports it at runtime, so it stays out of the app.js bundle.
set -eu

if [ $# -ne 1 ]; then
  echo "usage: $0 <pdfjs-dist version>" >&2
  echo "latest: npm view pdfjs-dist version" >&2
  exit 1
fi

version=$1
cd "$(git rev-parse --show-toplevel)"
dest=stashix_web/priv/static/vendor/pdfjs
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

(cd "$tmp" && npm pack --silent "pdfjs-dist@$version" >/dev/null && tar xzf pdfjs-dist-*.tgz)
pkg=$tmp/package

rm -rf "$dest"
mkdir -p "$dest/wasm"
cp "$pkg/LICENSE" "$pkg/build/pdf.min.mjs" "$pkg/build/pdf.worker.min.mjs" "$dest/"
# Fonts a PDF names without embedding, CJK character maps, colour profiles.
cp -r "$pkg/standard_fonts" "$pkg/cmaps" "$pkg/iccs" "$dest/"
# Image decoders (JPEG 2000, JBIG2) and colour management. QuickJS runs PDF
# form scripts, which the reader never does, so it is left out.
for f in openjpeg jbig2 qcms_bg; do cp "$pkg/wasm/$f"*.wasm "$dest/wasm/"; done
cp "$pkg/wasm/openjpeg_nowasm_fallback.js" "$pkg/wasm/jbig2_nowasm_fallback.js" "$dest/wasm/"
cp "$pkg/wasm/LICENSE_OPENJPEG" "$pkg/wasm/LICENSE_PDFJS_OPENJPEG" "$pkg/wasm/LICENSE_JBIG2" \
  "$pkg/wasm/LICENSE_PDFJS_JBIG2" "$pkg/wasm/LICENSE_QCMS" "$pkg/wasm/LICENSE_PDFJS_QCMS" "$dest/wasm/"
echo "$version" >"$dest/VERSION"

echo "PDF.js $version vendored in $dest ($(du -sh "$dest" | cut -f1))"
