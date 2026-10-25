#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cue vet -c ./tests
cue export -e cases ./tests > "$tmp/cases.json"

# Native spec fields and template metadata survive rendering unchanged, except
# identity, instances, and the default initdb supplied by orchestration.
jq -e '
  all(.[];
    . as $case |
    [.output.manifests.items[] | select(.kind == "Cluster")] as $clusters |
    [.output.manifests.items[] | select(.kind == "Deployment")] as $proxies |
    ($clusters | length) == .config.pg.shards and
    ($clusters | all(
      . as $cluster |
      .spec.instances == $case.config.pg.template.spec.instances and
      (($case.config.pg.template.spec | to_entries) | all(
        . as $entry | $cluster.spec[$entry.key] == $entry.value
      )) and
      (($case.config.pg.template.metadata | to_entries) | all(
        . as $entry | $cluster.metadata[$entry.key] | contains($entry.value)
      ))
    )) and
    ($proxies | length) == 1 and
    $proxies[0].spec.replicas == .config.dog.replicas and
    ($proxies[0].spec.template.spec.affinity // null) == (.config.dog.affinity // null) and
    ($proxies[0].spec.template.spec.topologySpreadConstraints // null) ==
      (.config.dog.topologySpreadConstraints // null) and
    ($proxies[0].spec.template.spec.containers[0].resources // null) ==
      (.config.dog.resources // null)
  ) and
  .defaults.config.pg.shards == 1 and
  .defaults.config.pg.template.spec.instances == 3 and
  .defaults.config.dog.replicas == 3 and
  (.defaults.output.manifests.items | all(
    if .kind == "Cluster" then
      .spec.affinity == null and .spec.postgresql == null and .spec.topologySpreadConstraints == null
    elif .kind == "Deployment" then
      .spec.template.spec.affinity == null and .spec.template.spec.topologySpreadConstraints == null
    else true end
  )) and
  .singleton.config.pg.template == .expanded.config.pg.template and
  .singleton.config.dog == .expanded.config.dog and
  .singleton.derived.shards[0] == .expanded.derived.shards[0] and
  ([.singleton.output.manifests.items[] | select(.kind == "Cluster")][0] ==
   [.expanded.output.manifests.items[] | select(.kind == "Cluster")][0]) and
  (.singleInstance.output.manifests.items | all(
    if .kind == "Cluster" then .spec.managed == null
    else true end
  ))
' "$tmp/cases.json" > /dev/null
echo "PASS: native templates pass through; no implicit placement/replication policy"
echo "PASS: one-to-four shards preserves the template, routing rules, and shard zero"

for name in defaults singleton expanded singleInstance nativeFields; do
  jq -r --arg name "$name" '
    .[$name].output.manifests.items[] |
    select(.kind == "ConfigMap" and .metadata.name == "pgdog") |
    .data["pgdog.toml"]
  ' "$tmp/cases.json" > "$tmp/config.toml"
  yq -p toml -o json '.' "$tmp/config.toml" > "$tmp/config.json"
  jq -e --arg name "$name" --slurpfile cases "$tmp/cases.json" '
    $cases[0][$name].config as $input |
    (.databases | length) == ($input.pg.shards * (if $input.pg.template.spec.instances > 1 then 2 else 1 end)) and
    (.databases | all(has("shard") and .shard >= 0 and .shard < $input.pg.shards)) and
    (.sharded_tables | length) == ($input.dog.shardedColumns | length) and
    (.sharded_schemas | length) == ($input.dog.shardedSchemas | length) and
    (if $input.pg.shards == 1 then (.databases | all(.shard == 0)) else true end)
  ' "$tmp/config.json" > /dev/null
  if [ "$name" = singleton ]; then cp "$tmp/config.json" "$tmp/singleton.json"; fi
  if [ "$name" = expanded ]; then
    jq -e --slurpfile old "$tmp/singleton.json" '
      [.databases[] | select(.shard == 0)] == $old[0].databases and
      .sharded_tables == $old[0].sharded_tables and
      .sharded_schemas == $old[0].sharded_schemas
    ' "$tmp/config.json" > /dev/null
  fi
  echo "PASS: $name uses the same PgDog backend/routing shape"
done

cue export -e invalid ./tests > "$tmp/invalid.json"
while IFS= read -r name; do
  jq --arg name "$name" '.[$name]' "$tmp/invalid.json" > "$tmp/input.json"
  if cue vet -c -d '#Case' ./tests "$tmp/input.json" > "$tmp/error.log" 2>&1; then
    echo "FAIL: invalid case $name was accepted"; exit 1
  fi
  grep -q 'conflicting\|explicit error\|invalid\|incompatible\|not allowed\|out of bound' "$tmp/error.log"
  echo "PASS: rejected $name"
done < <(jq -r 'keys[]' "$tmp/invalid.json")
