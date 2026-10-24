#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cue export -e topology . > "$tmp/topology.json"
yq -o=json '.' rendered/manifests.yaml > "$tmp/manifests.json"

case "${1:?expected manifests or pgdog}" in
  manifests)
    jq -e --slurpfile configs "$tmp/topology.json" '
      $configs[0] as $c |
      [.items[] | select(.kind == "Cluster")] as $clusters |
      [.items[] | select(.kind == "Service" and (.metadata.name | endswith("-read")))] as $reads |
      ($clusters | length) == $c.pg.shards and
      ($reads | length) == (if $c.pg.template.spec.instances > 1 then $c.pg.shards else 0 end) and
      ($clusters | all(.spec.instances == $c.pg.template.spec.instances)) and
      ($clusters | all(. as $cluster |
        ($c.pg.template.spec | to_entries | all(
          . as $entry | $cluster.spec[$entry.key] == $entry.value
        ))
      )) and
      ($reads | all(.spec.trafficDistribution == "PreferSameZone")) and
      all(range(0; $c.pg.shards);
        . as $i | ($clusters | any(.metadata.name == "\($c.name)-s\($i)")))
    ' "$tmp/manifests.json" > /dev/null
    echo "PASS: configured CNPG shard/instance counts and read services"
    ;;
  pgdog)
    jq -r '.items[] | select(.kind == "ConfigMap" and .metadata.name == "pgdog") |
      .data["pgdog.toml"]' "$tmp/manifests.json" > "$tmp/pgdog.toml"
    yq -p toml -o json '.' "$tmp/pgdog.toml" > "$tmp/pgdog.json"
    jq -e --slurpfile configs "$tmp/topology.json" '
      $configs[0] as $c |
      (.databases | length) == ($c.pg.shards * (if $c.pg.template.spec.instances > 1 then 2 else 1 end)) and
      (.databases | all(.name == $c.name and .database_name == $c.name)) and
      (.databases | all(.shard >= 0 and .shard < $c.pg.shards)) and
        .sharded_tables == [$c.dog.shardedColumns[] | {
          database: $c.name, column, data_type: .dataType
        } + (if has("name") then {name} else {} end) +
            (if has("mapping") then {mapping} else {} end)] and
        .sharded_schemas == [$c.dog.shardedSchemas[] | . + {database: $c.name}]
    ' "$tmp/pgdog.json" > /dev/null
    echo "PASS: PgDog backends and routing rules match topology"
    ;;
  *) echo "Unknown check: $1" >&2; exit 1 ;;
esac
