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
    cue export -e kindConfig --out yaml . > rendered/kind.yaml
    cue export -e manifests --out yaml . > rendered/manifests.yaml
    cue export -e secrets --out yaml . > rendered-secrets/secrets.yaml

# Structural assertions on rendered output. No cluster required.
check-manifests: render
    yq -e '[.items[] | select(.kind == "Cluster")] | length == 4' rendered/manifests.yaml > /dev/null
    for i in 0 1 2 3; do \
      yq -e "[.items[] | select(.kind == \"Cluster\" and .metadata.name == \"dog-s$i\")] | length == 1" rendered/manifests.yaml > /dev/null; \
      yq -e "[.items[] | select(.kind == \"Service\" and .metadata.name == \"dog-s$i-read\" and .spec.trafficDistribution == \"PreferSameZone\")] | length == 1" rendered/manifests.yaml > /dev/null; \
    done
    @echo "PASS: 4 shards, 4 read services with PreferSameZone"

# Re-render and fail if committed output is stale, or if the kind fixture drifted
check-render: render
    diff -u <(yq -P 'sort_keys(..)' kind.yaml) <(yq -P 'sort_keys(..)' rendered/kind.yaml)
    git diff --exit-code -- rendered/

fmt:
    cue fmt ./...

vet:
    cue vet ./...

# Apply rendered manifests, wave by wave
apply:
    @echo "not implemented until Task 8" && exit 1

# Apply schema and seed data through PgDog
seed:
    @echo "not implemented until Task 9" && exit 1

# Run all assertions
check:
    @echo "not implemented until Task 10" && exit 1

# Delete the kind cluster
down:
    kind delete cluster --name "${CLUSTER_NAME}"
