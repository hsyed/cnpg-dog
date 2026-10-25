#!/usr/bin/env bash
# Run cue with the image pins from flake.nix injected as tags.
set -euo pipefail
cd "$(dirname "$0")/.."
exec cue "$@" -t "pgdogImage=${PGDOG_IMAGE:?}" -t "pgImage=${PG_IMAGE:?}"
