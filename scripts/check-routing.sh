#!/usr/bin/env bash
set -euo pipefail
ns="${APP_NS:-dog}"
expected=400
total=0
maxshard=0
fail=0

for cluster in $(kubectl -n "$ns" get cluster -o jsonpath='{.items[*].metadata.name}'); do
  primary=$(kubectl -n "$ns" get cluster "$cluster" -o jsonpath='{.status.currentPrimary}')
  n=$(kubectl -n "$ns" exec "$primary" -c postgres -- \
        psql -U postgres -d dog -Atc "select count(*) from events")
  echo "$cluster: $n rows"
  total=$((total + n))
  [ "$n" -gt "$maxshard" ] && maxshard=$n
done

# 1. Completeness: nothing lost.
if [ "$total" -ne "$expected" ]; then
  echo "FAIL: total $total != expected $expected"; fail=1
else echo "PASS: all $expected rows accounted for"; fi

# 2. Partitioning: not everything on one shard.
if [ "$maxshard" -eq "$total" ]; then
  echo "FAIL: all rows on a single shard, not partitioned"; fail=1
else echo "PASS: rows partitioned, largest shard holds $maxshard/$total"; fi

# 3. Reachability: every seeded row retrievable through pgdog.
first=$(kubectl -n "$ns" get cluster -o jsonpath='{.items[0].metadata.name}')
primary=$(kubectl -n "$ns" get cluster "$first" -o jsonpath='{.status.currentPrimary}')
found=$(kubectl -n "$ns" exec "$primary" -c postgres -- \
  env PGPASSWORD=dogpassword psql -h pgdog -p 6432 -U dog -d dog -Atc "select count(*) from events" | tr -d '\r')
if [ "$found" != "$expected" ]; then
  echo "FAIL: pgdog sees $found rows, expected $expected"; fail=1
else echo "PASS: all $expected rows reachable through pgdog"; fi

exit $fail
