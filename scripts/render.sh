#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=${1:-rendered}
secrets=${2:-rendered-secrets}
mkdir -p "$output" "$secrets"
scripts/cue.sh export -e namespace --out yaml . > "$output/namespace.yaml"
scripts/cue.sh export -e manifests --out yaml . > "$output/manifests.yaml"
scripts/cue.sh export -e secrets --out yaml . > "$secrets/secrets.yaml"
scripts/cue.sh export -e 'assertSchema.out' --out text . > "$output/assert_schema.sql"
