#!/usr/bin/env bash
set -euo pipefail
ns="${APP_NS:-dog}"
fail=0

# Map node -> zone once.
declare -A zone_of
while read -r node zone; do zone_of["$node"]="$zone"; done < <(
  kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}{end}'
)

for cluster in $(kubectl -n "$ns" get cluster -o jsonpath='{.items[*].metadata.name}'); do
  zones=()
  while read -r pod node; do
    zones+=("${zone_of[$node]:-NONE}")
  done < <(kubectl -n "$ns" get pods -l "cnpg.io/cluster=$cluster" \
             -o jsonpath='{range .items[*]}{.metadata.name} {.spec.nodeName}{"\n"}{end}')

  uniq_count=$(printf '%s\n' "${zones[@]}" | sort -u | wc -l)
  if [ "$uniq_count" -ne "${#zones[@]}" ]; then
    echo "FAIL: $cluster has ${#zones[@]} instances across only $uniq_count zones: ${zones[*]}"
    fail=1
  else
    echo "PASS: $cluster spread across ${zones[*]}"
  fi

  # Sync replica must be outside the primary's zone.
  primary=$(kubectl -n "$ns" get cluster "$cluster" -o jsonpath='{.status.currentPrimary}')
  primary_node=$(kubectl -n "$ns" get pod "$primary" -o jsonpath='{.spec.nodeName}')
  primary_zone="${zone_of[$primary_node]}"
  sync_app=$(kubectl -n "$ns" exec "$primary" -c postgres -- \
    psql -U postgres -Atc "select application_name from pg_stat_replication where sync_state='sync'" | head -1)
  if [ -z "$sync_app" ]; then
    echo "FAIL: $cluster has no synchronous replica"
    fail=1
  else
    sync_node=$(kubectl -n "$ns" get pod "$sync_app" -o jsonpath='{.spec.nodeName}')
    if [ "${zone_of[$sync_node]}" = "$primary_zone" ]; then
      echo "FAIL: $cluster sync replica $sync_app shares zone $primary_zone with primary"
      fail=1
    else
      echo "PASS: $cluster sync replica in ${zone_of[$sync_node]}, primary in $primary_zone"
    fi
  fi
done
exit $fail
