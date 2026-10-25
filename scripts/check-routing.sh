#!/usr/bin/env bash
# Live routing assertions for the tests/local fixtures and topology.cue rules.
set -euo pipefail
cd "$(dirname "$0")/.."
name=$(scripts/cue.sh export -e topology.name --out text .)
user=$(scripts/cue.sh export -e credentials.username --out text .)
password=$(scripts/cue.sh export -e credentials.password --out text .)
fail=0

pass() { echo "PASS: $*"; }
failed() { echo "FAIL: $*"; fail=1; }

# Query one shard's primary directly, bypassing PgDog.
shard() {
  local primary
  primary=$(kubectl -n "$name" get cluster "$name-s$1" -o jsonpath='{.status.currentPrimary}')
  kubectl -n "$name" exec "$primary" -c postgres -- \
    psql -U postgres -d "$name" -Atc "$2" | tr -d '\r'
}
# Query through PgDog from inside the cluster.
pgdog() {
  local primary
  primary=$(kubectl -n "$name" get cluster "$name-s0" -o jsonpath='{.status.currentPrimary}')
  kubectl -n "$name" exec "$primary" -c postgres -- env PGPASSWORD="$password" \
    psql -h pgdog -p 6432 -U "$user" -d "$name" -Atc "$1" | tr -d '\r'
}
expect() { # description, actual, expected
  if [ "$2" = "$3" ]; then pass "$1"; else failed "$1: got '$2', expected '$3'"; fi
}

shards=$(kubectl -n "$name" get cluster -o name | wc -l)

# Hash (bigint): complete, spread over every shard, reachable through PgDog.
total=0
for i in $(seq 0 $((shards - 1))); do
  n=$(shard "$i" "select count(*) from events")
  echo "$name-s$i: $n events"
  [ "$n" -gt 0 ] || failed "$name-s$i holds no events; hash routing not partitioning"
  total=$((total + n))
done
expect "all events accounted for" "$total" 400
expect "all events reachable through PgDog" "$(pgdog "select count(*) from events")" 400

# List and range: exact shard per fixture row (see tests/local/sql/seed.sql).
regions=(ca,us eu jp "")
orders=(1,99 100,199 200,500 "")
for i in 0 1 2 3; do
  expect "list routing on $name-s$i" \
    "$(shard "$i" "select coalesce(string_agg(region, ',' order by region), '') from regions")" "${regions[$i]}"
  expect "range routing on $name-s$i" \
    "$(shard "$i" "select coalesce(string_agg(order_id::text, ',' order by order_id), '') from orders")" "${orders[$i]}"
done

# Hash (uuid): complete and reachable.
users=0
for i in $(seq 0 $((shards - 1))); do
  users=$((users + $(shard "$i" "select count(*) from users")))
done
expect "all users accounted for" "$users" 8
expect "all users reachable through PgDog" "$(pgdog "select count(*) from users")" 8

# Schema routing: each tenant schema exists only on its shard.
schemas=(customer_a customer_b "" "")
for i in 0 1 2 3; do
  expect "schema routing on $name-s$i" \
    "$(shard "$i" "select coalesce(string_agg(nspname, ',' order by nspname), '') from pg_namespace where nspname like 'customer\_%'")" "${schemas[$i]}"
done
expect "customer_a reachable through PgDog" "$(pgdog "select body from customer_a.notes")" a
expect "customer_b reachable through PgDog" "$(pgdog "select body from customer_b.notes")" b

exit "$fail"
