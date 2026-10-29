#!/bin/sh
# Stand-in for the two unrar commands Stashix uses, on top of 7z (Alpine ships
# no unrar). Switches before "--" are skipped; everything after is a file name.
set -e

cmd="$1"
shift

while [ $# -gt 0 ]; do
  case "$1" in
    --) shift; break ;;
    -*) shift ;;
    *) break ;;
  esac
done

case "$cmd" in
  lb) 7z l -ba -slt -- "$1" | sed -n 's/^Path = //p' ;;
  p) 7z x -so -- "$1" "$2" ;;
  *) echo "unsupported: $cmd" >&2; exit 1 ;;
esac
