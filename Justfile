set shell := ["bash", "-euo", "pipefail", "-c"]

# List available recipes
default:
    @just --list

# Create the kind cluster and install the CNPG operator
up: kind-up operator-up

kind-up:
    kind create cluster --config kind.yaml --image "${KIND_NODE_IMAGE}" --wait 120s
    kubectl config use-context "kind-${CLUSTER_NAME}"

operator-up:
    kubectl apply --server-side -f "${CNPG_MANIFEST}"
    kubectl -n cnpg-system wait --for=condition=Available deployment/cnpg-controller-manager --timeout=180s

# Render CUE to plain YAML. PURE: touches no cluster, reads no environment.
render:
    mkdir -p rendered rendered-secrets
    cue export -e kindConfig --out yaml ./render > rendered/kind.yaml
    cue export -e namespace --out yaml ./render > rendered/namespace.yaml
    cue export -e manifests --out yaml -t pgdogImage="${PGDOG_IMAGE}" ./render > rendered/manifests.yaml
    cue export -e secrets --out yaml ./render > rendered-secrets/secrets.yaml
    cue export -e 'assertSchema.out' --out text ./render > rendered/assert_schema.sql

# Structural assertions on rendered output. No cluster required.
check-manifests: render
    yq -e '[.items[] | select(.kind == "Cluster")] | length == 4' rendered/manifests.yaml > /dev/null
    for i in 0 1 2 3; do \
      yq -e "[.items[] | select(.kind == \"Cluster\" and .metadata.name == \"dog-s$i\")] | length == 1" rendered/manifests.yaml > /dev/null; \
      yq -e "[.items[] | select(.kind == \"Service\" and .metadata.name == \"dog-s$i-read\" and .spec.trafficDistribution == \"PreferSameZone\")] | length == 1" rendered/manifests.yaml > /dev/null; \
    done
    @echo "PASS: 4 shards, 4 read services with PreferSameZone"

# Assert the rendered pgdog.toml has the expected routing table.
check-pgdog-config: render
    yq -r '.items[] | select(.kind == "ConfigMap" and .metadata.name == "pgdog") | .data["pgdog.toml"]' rendered/manifests.yaml > /tmp/pgdog-rendered.toml
    test "$(grep -c '^\[\[databases\]\]' /tmp/pgdog-rendered.toml)" = "8"
    test "$(grep -c '^\[\[sharded_tables\]\]' /tmp/pgdog-rendered.toml)" = "2"
    grep -q 'shard = 3' /tmp/pgdog-rendered.toml
    grep -q "host = 'dog-s3-read'" /tmp/pgdog-rendered.toml
    grep -q "name = 'events'" /tmp/pgdog-rendered.toml
    grep -q "name = 'orders'" /tmp/pgdog-rendered.toml
    @echo "PASS: 8 database entries (4 shards x primary+replica), 2 sharded tables"

# Re-render and fail if committed output is stale, or if the kind fixture drifted
check-render: render
    diff -u <(yq -P 'sort_keys(..)' kind.yaml) <(yq -P 'sort_keys(..)' rendered/kind.yaml)
    git diff --exit-code -- rendered/

fmt:
    cue fmt ./...
vet:
    cue vet -t pgdogImage="${PGDOG_IMAGE}" ./...

# Apply rendered manifests, wave by wave
apply: render
    kubectl apply --server-side -f rendered/namespace.yaml
    kubectl apply --server-side -f rendered-secrets/secrets.yaml
    kubectl apply --server-side -f rendered/manifests.yaml
    just wait

wait:
    kubectl -n "${APP_NS}" wait --for=condition=Ready cluster --all --timeout=600s

# Apply schema and seed data through PgDog
seed: render
    kubectl -n "${APP_NS}" run psql-probe --rm -i --restart=Never \
      --image="${PG_IMAGE}" --env=PGPASSWORD=dogpassword -- \
      psql -h pgdog -p 6432 -U dog -d dog -v ON_ERROR_STOP=1 -f - < sql/schema.sql
    kubectl -n "${APP_NS}" run psql-probe --rm -i --restart=Never \
      --image="${PG_IMAGE}" --env=PGPASSWORD=dogpassword -- \
      psql -h pgdog -p 6432 -U dog -d dog -v ON_ERROR_STOP=1 -f - < rendered/assert_schema.sql
    kubectl -n "${APP_NS}" run psql-probe --rm -i --restart=Never \
      --image="${PG_IMAGE}" --env=PGPASSWORD=dogpassword -- \
      psql -h pgdog -p 6432 -U dog -d dog -v ON_ERROR_STOP=1 -f - < sql/seed.sql

# Run all assertions
check: check-render check-manifests check-pgdog-config
    bash scripts/check-placement.sh
    bash scripts/check-routing.sh
    @echo "ALL CHECKS PASSED"

# Delete the kind cluster
down:
    kind delete cluster --name "${CLUSTER_NAME}"
