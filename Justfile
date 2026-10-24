set shell := ["bash", "-euo", "pipefail", "-c"]

# List available recipes
default:
    @just --list

# Create the kind cluster and install the CNPG operator
up: kind-up operator-up

kind-up: render
    kind create cluster --config rendered/kind.yaml --image "${KIND_NODE_IMAGE}" --wait 120s
    kubectl config use-context "kind-$(yq -r '.name' rendered/kind.yaml)"

operator-up:
    kubectl apply --server-side -f "${CNPG_MANIFEST}"
    kubectl -n cnpg-system wait --for=condition=Available deployment/cnpg-controller-manager --timeout=180s

# Render CUE to plain YAML. PURE: touches no cluster, reads no environment.
render:
    bash scripts/render.sh

# Structural assertions on rendered output. No cluster required.
check-manifests: render
    bash scripts/check-generated.sh manifests

# Assert the rendered pgdog.toml has the expected routing table.
check-pgdog-config: render
    bash scripts/check-generated.sh pgdog

# Compare fresh output with the reviewed snapshots, including uncommitted edits
check-render:
    @tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT; \
      bash scripts/render.sh "$tmp/rendered" "$tmp/secrets"; \
      diff -ru rendered "$tmp/rendered"

# Exercise topology, native templates, and local kind configuration offline
check-topology:
    bash scripts/check-topology.sh

# Regenerate native schemas from the release pins in flake.nix
update-schemas:
    bash scripts/update-schemas.sh

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
check: check-render check-manifests check-pgdog-config check-topology
    bash scripts/check-placement.sh
    bash scripts/check-routing.sh
    @echo "ALL CHECKS PASSED"

# Delete the kind cluster
down:
    kind delete cluster --name "$(cue export -e kindConfig.name --out text .)"
