set shell := ["bash", "-euo", "pipefail", "-c"]

# List available recipes
default:
    @just --list

# Create the kind cluster and install the CNPG operator
up:
    @echo "not implemented until Task 2/3" && exit 1

# Render CUE to plain YAML. PURE: touches no cluster, reads no environment.
render:
    @echo "not implemented until Task 5" && exit 1

# Apply rendered manifests, wave by wave
apply:
    @echo "not implemented until Task 8" && exit 1

# Apply schema and seed data through PgDog
seed:
    @echo "not implemented until Task 9" && exit 1

# Run all assertions
check:
    @echo "not implemented until Task 10" && exit 1

# Re-render and fail if the committed output is stale
check-render:
    @echo "not implemented until Task 5" && exit 1

# Delete the kind cluster
down:
    kind delete cluster --name "${CLUSTER_NAME}"
