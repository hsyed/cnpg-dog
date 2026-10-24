#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ns="${APP_NS:-dog}"
fail=0
config=$(cue export -e topology .)
instances=$(jq -r '.pg.template.spec.instances' <<< "$config")
proxies=$(jq -r '.dog.replicas' <<< "$config")
nodes=$(kubectl get nodes -o json)

check_group() {
  local selector=$1 expected=$2 name=$3 pods
  pods=$(kubectl -n "$ns" get pods -l "$selector" -o json)
  group_nodes=$(jq '[.items[].spec.nodeName // ""]' <<< "$pods")
  if ! jq -e --argjson expected "$expected" '
    (.items | length) == $expected and all(.items[];
      (.spec.nodeName // "") != "" and
      any(.status.conditions[]?; .type == "Ready" and .status == "True"))
  ' <<< "$pods" > /dev/null; then
    echo "FAIL: $name does not have $expected scheduled, ready pods"
    fail=1
    return 1
  fi
  echo "PASS: $name has $expected ready pods on $(jq -r 'join(", ")' <<< "$group_nodes")"
}

clusters=$(kubectl -n "$ns" get cluster -o json)
if [ "$(jq '.items | length' <<< "$clusters")" -eq 0 ]; then
  echo "FAIL: no CNPG clusters found"; exit 1
fi
for cluster in $(jq -r '.items[].metadata.name' <<< "$clusters"); do
  check_group "cnpg.io/cluster=$cluster,cnpg.io/podRole=instance" "$instances" "$cluster" || continue
  spec=$(jq --arg name "$cluster" '.items[] | select(.metadata.name == $name) | .spec' <<< "$clusters")

  # Check CNPG's declared required anti-affinity, not an inferred AZ preset.
  if jq -e '.affinity.enablePodAntiAffinity != false and
    .affinity.podAntiAffinityType == "required"' <<< "$spec" > /dev/null; then
    key=$(jq -r '(.affinity.topologyKey // "") as $key |
      if $key == "" then "kubernetes.io/hostname" else $key end' <<< "$spec")
    domains=$(jq --arg key "$key" --argjson names "$group_nodes" '
      [.items[] | select(.metadata.name as $name | $names | index($name)) |
       .metadata.labels[$key] // null]
    ' <<< "$nodes")
    if ! jq -e --argjson expected "$instances" '
      all(.[]; . != null) and (unique | length) == $expected
    ' <<< "$domains" > /dev/null; then
      echo "FAIL: $cluster violates required anti-affinity on $key"; fail=1
    else
      echo "PASS: $cluster satisfies required anti-affinity on $key"
    fi
  fi

  # CNPG owns replication semantics. Verify required modern sync policies
  # using both priority (sync) and quorum (quorum) replication states.
  number=$(jq -r '.postgresql.synchronous.number // 0' <<< "$spec")
  durability=$(jq -r '.postgresql.synchronous.dataDurability // "required"' <<< "$spec")
  if [ "$number" -gt 0 ] && [ "$durability" = required ]; then
    primary=$(jq -r --arg name "$cluster" '
      .items[] | select(.metadata.name == $name) | .status.currentPrimary' <<< "$clusters")
    ready=$(kubectl -n "$ns" exec "$primary" -c postgres -- \
      psql -U postgres -Atc "select count(*) from pg_stat_replication where state='streaming' and sync_state in ('sync','quorum')")
    ready=${ready//$'\r'/}
    if [ "$ready" -lt "$number" ]; then
      echo "FAIL: $cluster has $ready synchronous candidates, requires $number"; fail=1
    else
      echo "PASS: $cluster satisfies its required synchronous replication count"
    fi
  fi
done
check_group "app=pgdog" "$proxies" "PgDog" || true
exit "$fail"
