set shell := ["bash", "-euo", "pipefail", "-c"]

# List available recipes
default:
    @just --list

# Create the kind cluster and install the CNPG operator
up: kind-up operator-up

kind-up:
    kind create cluster --config tests/local/kind.yaml --image "${KIND_NODE_IMAGE}" --wait 120s
    kubectl config use-context "kind-$(yq -r '.name // "kind"' tests/local/kind.yaml)"

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

# Exercise topology and native templates offline
check-topology:
    bash scripts/check-topology.sh

# Regenerate native schemas from the release pins in flake.nix
update-schemas:
    bash scripts/update-schemas.sh

fmt:
    cue fmt ./...
vet:
    scripts/cue.sh vet ./...

# Apply rendered manifests, wave by wave
apply: render
    kubectl apply --server-side -f rendered/namespace.yaml
    kubectl apply --server-side -f rendered-secrets/secrets.yaml
    kubectl apply --server-side -f rendered/manifests.yaml
    just wait

wait:
    ns="$(scripts/cue.sh export -e topology.name --out text .)"; \
      kubectl -n "$ns" wait --for=condition=Ready cluster --all --timeout=600s

# PgDog pods started before the tables existed route keyless reads on
# column-only rules to a single shard (observed on v0.1.53), so seeding
# restarts PgDog between the DDL and the data.
# Apply schema and type assertions, then seed data, through PgDog
seed: render
    name="$(scripts/cue.sh export -e topology.name --out text .)"; \
      user="$(scripts/cue.sh export -e credentials.username --out text .)"; \
      pw="$(scripts/cue.sh export -e credentials.password --out text .)"; \
      psql() { \
        kubectl -n "$name" delete pod psql-probe --ignore-not-found; \
        cat "$@" | kubectl -n "$name" run psql-probe --rm -i --restart=Never \
          --image="${PG_IMAGE}" --env=PGPASSWORD="$pw" -- \
          psql -h pgdog -p 6432 -U "$user" -d "$name" -v ON_ERROR_STOP=1 -f -; \
      }; \
      psql tests/local/sql/schema.sql rendered/assert_schema.sql; \
      kubectl -n "$name" rollout restart deployment/pgdog; \
      kubectl -n "$name" rollout status deployment/pgdog --timeout=180s; \
      psql tests/local/sql/seed.sql

# Run all assertions
check: check-render check-manifests check-pgdog-config check-topology
    bash scripts/check-placement.sh
    bash scripts/check-routing.sh
    @echo "ALL CHECKS PASSED"

# Delete the kind cluster
down:
    kind delete cluster --name "$(yq -r '.name // "kind"' tests/local/kind.yaml)"
