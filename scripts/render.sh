#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=${1:-rendered}
secrets=${2:-rendered-secrets}
mkdir -p "$output" "$secrets"
cue export -e namespace --out yaml . > "$output/namespace.yaml"
cue export -e manifests --out yaml -t "pgdogImage=${PGDOG_IMAGE:?}" . > "$output/manifests.yaml"
cue export -e secrets --out yaml . > "$secrets/secrets.yaml"
cue export -e 'assertSchema.out' --out text . > "$output/assert_schema.sql"
