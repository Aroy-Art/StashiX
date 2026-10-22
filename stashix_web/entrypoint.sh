#!/bin/sh
set -e

# Started as root: fix ownership of the data dir, then drop to PUID:PGID so the
# server itself never runs as root. Started with --user: run as that user as-is.
if [ "$(id -u)" = "0" ]; then
  PUID="${PUID:-1000}"
  PGID="${PGID:-1000}"

  case "$PUID$PGID" in
    *[!0-9]*)
      echo "PUID and PGID must be numeric (got PUID=$PUID PGID=$PGID)" >&2
      exit 1
      ;;
  esac

  mkdir -p "$DATA_DIR"
  if [ "$(stat -c '%u:%g' "$DATA_DIR")" != "$PUID:$PGID" ]; then
    echo "Setting ownership of $DATA_DIR to $PUID:$PGID"
    chown -R "$PUID:$PGID" "$DATA_DIR"
  fi

  export HOME=/tmp
  run="su-exec $PUID:$PGID"
else
  run=""
fi

$run ./bin/stashix eval "Stashix.Release.migrate()"
exec $run ./bin/stashix start
