#!/bin/sh
set -e

./bin/stashix eval "Stashix.Release.migrate()"
exec ./bin/stashix start
