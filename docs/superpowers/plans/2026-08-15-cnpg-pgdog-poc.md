# CNPG + PgDog Sharding POC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local `kind` cluster running four CloudNativePG-managed Postgres shards spread across three simulated availability zones, fronted by PgDog for sharded routing, with the entire topology derived from a single CUE value.

**Architecture:** Three pure layers in CUE — `topology.cue` (knobs) → `fabric.cue` (derived names and endpoints) → renderers (`render/*.cue`). Both the CNPG `Cluster` resources and PgDog's routing table are functions of the same `fabric` value, so they cannot drift. `cue export` produces plain YAML into `rendered/`, which `just` applies with `kubectl`. No Argo, no Helm, no Timoni.

**Tech Stack:** CUE, Nix flakes, `just`, kind, CloudNativePG 1.30.0, PgDog v0.1.53, PostgreSQL 18.

**Spec:** `docs/superpowers/specs/2026-08-15-cnpg-pgdog-poc-design.md` — read it before starting. This plan argues from it.

## Global Constraints

Exact values. Every task inherits these.

- **kind node image:** `kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5` (kind v0.32.0's default; Kubernetes 1.36 is the latest CNPG 1.30-supported version and well past the `trafficDistribution` GA floor of 1.33).
- **CNPG operator:** `https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.30/releases/cnpg-1.30.0.yaml`, installs into namespace `cnpg-system`.
- **PgDog image:** `ghcr.io/pgdogdev/pgdog:v0.1.53`. Config via `pgdog --config /etc/pgdog/pgdog.toml --users /etc/pgdog/users.toml`.
- **Postgres image:** `ghcr.io/cloudnative-pg/postgresql:18.4`.
- **Application namespace:** `dog`. **Cluster name prefix:** `dog`. **Shards:** 4 (`dog-s0`..`dog-s3`). **Zones:** `a`, `b`, `c`.
- **Every version pin lives in `flake.nix` and nowhere else.** Tasks read them from environment variables exported by the devShell. Never hardcode a version in the Justfile or a CUE file.
- **`just render` must never read cluster state or the environment.** It is a pure function. Only `just apply`, `just up`, `just seed` and `just check` may touch a cluster.
- All commands are run inside the devShell: `nix develop -c <cmd>`, or from a `nix develop` shell.
- Commit after every task. Conventional commit prefixes (`feat:`, `chore:`, `test:`, `docs:`).

### Deviation from spec §6.1, recorded deliberately

The spec calls for `cue vet` against *vendored* Kubernetes and CNPG schemas. This plan hand-writes minimal partial schemas instead (`schema/k8s.cue`, `schema/cnpg.cue`) and uses **`kubectl apply --dry-run=server`** as the authoritative schema gate. Rationale: vendoring CUE definitions from the CNPG CRD requires either a Go toolchain plus `cue get go`, or Timoni's `mod vendor crd` — both add tooling risk to a POC for validation that server-side dry-run performs better anyway, against the real API server. `cue vet` still checks every constraint we author ourselves. Partial schemas must carry a comment saying they are POC-grade and intentionally incomplete.

### Deviation from spec §5, recorded deliberately

CUE packages are directory-scoped, so the spec's three-level layout maps to
three packages connected by imports, and the repo root holds **no `.cue`
files**:

- `schema/` (`package schema`) — pure definitions (`#Topology`, `#Shard`,
  `#Fabric`, `#ShardedTable`, plus the POC-grade k8s/CNPG defs). Leaf package.
- `model/` (`package model`) — the knobs (`model/topology.cue`) and the single
  derivation (`model/fabric.cue`). Imports `schema`.
- `render/` (`package render`) — the renderers and the top-level exports
  (`kindConfig`, `namespace`, `manifests`, `secrets`, `assertSchema`). Imports
  `model` for `fabric` and `schema` for the definitions.

The `just render` recipes export from `./render` (`cue export -e kindConfig
./render`), not from `.`.

This preserves the spec's layering and the "one value read twice" property:
renderers read `model.fabric`, they never re-derive a name.

---

## File Structure

```
flake.nix                     devShell + every version pin
.envrc                        direnv hook (optional convenience)
.gitignore                    excludes rendered-secrets/
Justfile                      the verbs
cue.mod/module.cue            CUE module definition
schema/
  k8s.cue                     #ConfigMap #Secret #Service #Deployment (partial, POC-grade)
  cnpg.cue                    #CNPGCluster (partial, POC-grade)
  topology.cue                #Topology #Shard #Fabric #ShardedTable
topology.cue                  THE KNOBS — the only file edited day to day
fabric.cue                    topology -> fabric derivation
render/
  kind.cue                    kind cluster config
  cnpg.cue                    Cluster CRs + read Services
  pgdog.cue                   ConfigMap(pgdog.toml) + Secret + Deployment + Service
  namespace.cue               Namespace + app credentials Secret
  manifests.cue               top-level export, sync-wave annotated
sql/
  schema.sql                  hand-written DDL
  seed.sql                    hand-written seed data
rendered/                     committed golden YAML; also a valid Argo source
rendered-secrets/             gitignored, applied but never committed
scripts/
  check-placement.sh          zone spread + sync replica assertions
  check-routing.sh            partition/completeness/reachability assertions
docs/reference/
  pgdog-config.md             VERIFIED pgdog.toml keys (produced by Task 4)
```

---

## Task 1: Nix flake and Justfile skeleton

**Files:**
- Create: `flake.nix`, `.envrc`, `.gitignore`, `Justfile`, `README.md`

**Interfaces:**
- Consumes: nothing.
- Produces: devShell exporting `KIND_NODE_IMAGE`, `CNPG_MANIFEST`, `PGDOG_IMAGE`, `PG_IMAGE`, `CLUSTER_NAME`, `APP_NS`. Every later task reads these rather than hardcoding.

- [ ] **Step 1: Write `flake.nix`**

```nix
{
  description = "CNPG + PgDog sharding POC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            cue
            just
            kind
            kubectl
            kubectl-cnpg
            postgresql_18
            jq
            yq-go
          ];

          # Single home for every version pin. Nothing else may hardcode these.
          KIND_NODE_IMAGE = "kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5";
          CNPG_MANIFEST = "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.30/releases/cnpg-1.30.0.yaml";
          PGDOG_IMAGE = "ghcr.io/pgdogdev/pgdog:v0.1.53";
          PG_IMAGE = "ghcr.io/cloudnative-pg/postgresql:18.4";
          CLUSTER_NAME = "cnpg-dog";
          APP_NS = "dog";
        };
      });
}
```

- [ ] **Step 2: Write `.gitignore`**

```
rendered-secrets/
.direnv/
result
```

- [ ] **Step 3: Write `.envrc`**

```
use flake
```

- [ ] **Step 4: Write the `Justfile` skeleton**

Recipes are stubs that `exit 1` with a message naming the task that fills them in. This makes `just --list` the plan's table of contents from day one.

```make
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
```

- [ ] **Step 5: Verify the shell builds and tools resolve**

Run:
```bash
nix develop -c bash -c 'cue version && just --version && kind version && kubectl version --client=true -o yaml | head -3 && psql --version && echo "$KIND_NODE_IMAGE"'
```
Expected: every command prints a version, and the node image string prints with its digest. If `kubectl-cnpg` or `postgresql_18` fails to resolve under the pinned nixpkgs, substitute the nearest available attribute name and record the substitution in `README.md`.

- [ ] **Step 6: Verify `just` lists recipes**

Run: `nix develop -c just`
Expected: the recipe list prints with all nine recipes and their doc comments.

- [ ] **Step 7: Write a short `README.md`**

Three sections: what this is (one paragraph, linking the spec), how to run it (`nix develop`, then `just up && just apply && just seed && just check`), and a "version pins live in flake.nix" note.

- [ ] **Step 8: Commit**

```bash
git add flake.nix flake.lock .envrc .gitignore Justfile README.md
git commit -m "feat: nix devshell and justfile skeleton with pinned versions"
```

---

## Task 2: kind cluster with zone-labeled workers

**Files:**
- Create: `kind.yaml` (hand-written; becomes the golden fixture that Task 5's CUE renderer must reproduce byte for byte)
- Modify: `Justfile` (the `up` recipe)

**Interfaces:**
- Consumes: `$KIND_NODE_IMAGE`, `$CLUSTER_NAME` from Task 1's devShell.
- Produces: `kind.yaml` as the expected-output fixture for Task 5. A running cluster named `cnpg-dog` with three workers labeled `topology.kubernetes.io/zone` = `a`, `b`, `c`.

- [ ] **Step 1: Write `kind.yaml` by hand**

This file is deliberately hand-written first. In Task 5 the CUE renderer must reproduce it exactly, which turns it into a real test of the renderer rather than a snapshot of whatever the renderer happened to emit.

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: cnpg-dog
nodes:
- role: control-plane
- role: worker
  labels:
    topology.kubernetes.io/zone: a
- role: worker
  labels:
    topology.kubernetes.io/zone: b
- role: worker
  labels:
    topology.kubernetes.io/zone: c
```

- [ ] **Step 2: Replace the `up` recipe in the `Justfile`**

```make
# Create the kind cluster and install the CNPG operator
up: kind-up

kind-up:
    kind create cluster --config kind.yaml --image "${KIND_NODE_IMAGE}" --wait 120s
    kubectl config use-context "kind-${CLUSTER_NAME}"
```

- [ ] **Step 3: Create the cluster**

Run: `nix develop -c just up`
Expected: kind reports all nodes ready within 120s. If the image digest is rejected by kind v0.32.0, drop to `kindest/node:v1.36.1` without the digest, confirm the cluster boots, then record the change in `flake.nix` and note why in `README.md`.

- [ ] **Step 4: Write the zone-label assertion and run it**

Run:
```bash
nix develop -c bash -c '
  zones=$(kubectl get nodes -l "!node-role.kubernetes.io/control-plane" \
    -o jsonpath="{.items[*].metadata.labels.topology\.kubernetes\.io/zone}" | tr " " "\n" | sort -u)
  echo "$zones"
  test "$(echo "$zones" | tr "\n" " ")" = "a b c " || { echo "FAIL: expected zones a b c"; exit 1; }
  echo "PASS: three distinct zones"'
```
Expected: prints `a`, `b`, `c` then `PASS: three distinct zones`. This is the first half of the Milestone 0 gate.

- [ ] **Step 5: Commit**

```bash
git add kind.yaml Justfile
git commit -m "feat: kind cluster with three zone-labeled workers"
```

---

## Task 3: CNPG operator, and prove zone spread works before building on it

**Files:**
- Create: `scratch/probe-cluster.yaml` (throwaway, deleted at the end of this task — do not commit it)
- Modify: `Justfile` (`up` recipe gains operator install)

**Interfaces:**
- Consumes: running kind cluster from Task 2, `$CNPG_MANIFEST`, `$PG_IMAGE`.
- Produces: a verified answer to "does a 3-instance CNPG cluster actually land one pod per zone on three workers, and does `syncReplicaElectionConstraint` work alongside the `spec.postgresql.synchronous` API?" — recorded in `docs/reference/cnpg-placement.md`. Task 6 copies the verified field spellings from that file.

This task exists because the whole multi-zone claim rests on CNPG field names and behaviour that have not been verified on a real cluster. Finding out here costs minutes; finding out inside the CUE renderer costs a day.

- [ ] **Step 1: Extend the `up` recipe**

```make
up: kind-up operator-up

operator-up:
    kubectl apply --server-side -f "${CNPG_MANIFEST}"
    kubectl -n cnpg-system wait --for=condition=Available deployment/cnpg-controller-manager --timeout=180s
```

- [ ] **Step 2: Install the operator**

Run: `nix develop -c just operator-up`
Expected: the deployment becomes Available. If the deployment name differs from `cnpg-controller-manager`, get the real name with `kubectl -n cnpg-system get deploy -o name` and correct the recipe.

- [ ] **Step 3: Write the throwaway probe cluster**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: probe
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: probe-s0
  namespace: probe
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:18.4
  storage:
    size: 256Mi
  postgresql:
    synchronous:
      method: any
      number: 1
    syncReplicaElectionConstraint:
      enabled: true
      nodeLabelsAntiAffinity:
      - topology.kubernetes.io/zone
  topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        cnpg.io/cluster: probe-s0
```

- [ ] **Step 4: Server-side dry-run it first**

Run: `nix develop -c kubectl apply --server-side --dry-run=server -f scratch/probe-cluster.yaml`
Expected: accepted. **If the API server rejects `postgresql.synchronous` or `syncReplicaElectionConstraint`,** that is the finding this task exists to produce. Consult `kubectl explain cluster.spec.postgresql --recursive` for the real field names under CNPG 1.30, correct the YAML, and record both the wrong and right spellings in `docs/reference/cnpg-placement.md`.

- [ ] **Step 5: Apply it for real and wait**

Run:
```bash
nix develop -c bash -c 'kubectl apply --server-side -f scratch/probe-cluster.yaml
kubectl -n probe wait --for=condition=Ready cluster/probe-s0 --timeout=300s'
```
Expected: the cluster reaches Ready. If the condition name is not `Ready`, find it with `kubectl -n probe get cluster probe-s0 -o jsonpath='{.status.conditions}' | jq` and record the correct one — Task 6 and the Justfile both need it.

- [ ] **Step 6: Verify one pod per zone**

Run:
```bash
nix develop -c bash -c '
  kubectl -n probe get pods -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName --no-headers
  for z in a b c; do
    n=$(kubectl -n probe get pods -o json | jq --arg z "$z" "[.items[] | select(.spec.nodeName | test(\"worker\"))] | length")
    echo "zone $z: check node labels manually via kubectl get nodes -L topology.kubernetes.io/zone"
  done
  kubectl get nodes -L topology.kubernetes.io/zone'
```
Expected: three pods on three distinct worker nodes, and those three workers carry zones `a`, `b`, `c`. Cross-check by eye here; Task 7 automates the assertion properly.

- [ ] **Step 7: Verify the sync replica is cross-zone**

Run:
```bash
nix develop -c bash -c '
  kubectl -n probe get cluster probe-s0 -o jsonpath="{.status.currentPrimary}"; echo
  kubectl -n probe exec probe-s0-1 -c postgres -- \
    psql -U postgres -Atc "select application_name, sync_state from pg_stat_replication"'
```
Expected: exactly one replica reports `sync`, the rest `async` (or `potential`). Note which pod is primary and which is the sync replica, and confirm they sit in different zones. If `probe-s0-1` is not the primary, run the `psql` against whichever pod `currentPrimary` names.

- [ ] **Step 8: Record the verified findings**

Create `docs/reference/cnpg-placement.md` containing: the exact verified `spec.postgresql.synchronous` and `syncReplicaElectionConstraint` YAML as applied, the correct readiness condition name, the pod label key that identifies replicas (get it with `kubectl -n probe get pod probe-s0-2 --show-labels` — expected `cnpg.io/instanceRole=replica`, but verify), and observed zone placement. Task 6, Task 7 and Task 8 all read this file.

- [ ] **Step 9: Tear down the probe and commit**

```bash
kubectl delete ns probe --wait=false
rm -rf scratch/
git add Justfile docs/reference/cnpg-placement.md
git commit -m "feat: install CNPG operator; verify zone spread and sync replica election"
```

---

## Task 4: Verify PgDog's real config format against the pinned image

**Files:**
- Create: `docs/reference/pgdog-config.md`, `scratch/pgdog.toml`, `scratch/users.toml` (the scratch files are throwaway; the reference doc is the deliverable)

**Interfaces:**
- Consumes: `$PGDOG_IMAGE`.
- Produces: `docs/reference/pgdog-config.md` — a verbatim, **verified-against-the-binary** `pgdog.toml` and `users.toml`. Task 8's CUE renderer must emit exactly these key names. This is the single highest-risk unknown in the project (spec §9).

Do not skip or shortcut this task. Everything in Task 8 is built on its output. The key names below are the plan author's best reading of PgDog's documentation and are **explicitly unverified** — the point of this task is to correct them.

- [ ] **Step 1: Discover the CLI surface**

Run:
```bash
nix develop -c docker run --rm "${PGDOG_IMAGE}" --help
```
Expected: a flag list. Look specifically for a config-validation or dry-run flag (`--check`, `--validate`, `--dry-run`). If one exists, prefer it for steps 4 and 5 — it gives a clean parse-only signal.

- [ ] **Step 2: Write the candidate `scratch/pgdog.toml`**

Two shards, primary and replica each, matching the shape Task 8 must generate.

```toml
[general]
host = "0.0.0.0"
port = 6432
workers = 2
default_pool_size = 10

[[databases]]
name = "dog"
host = "dog-s0-rw"
port = 5432
role = "primary"
shard = 0
database_name = "dog"

[[databases]]
name = "dog"
host = "dog-s0-read"
port = 5432
role = "replica"
shard = 0
database_name = "dog"

[[databases]]
name = "dog"
host = "dog-s1-rw"
port = 5432
role = "primary"
shard = 1
database_name = "dog"

[[databases]]
name = "dog"
host = "dog-s1-read"
port = 5432
role = "replica"
shard = 1
database_name = "dog"

[[sharded_tables]]
database = "dog"
table = "events"
column = "tenant_id"
data_type = "bigint"
```

- [ ] **Step 3: Write the candidate `scratch/users.toml`**

```toml
[[users]]
name = "dog"
database = "dog"
password = "dogpassword"
```

- [ ] **Step 4: Run PgDog against the candidate config**

```bash
nix develop -c docker run --rm -v "$PWD/scratch:/etc/pgdog:ro" "${PGDOG_IMAGE}" \
  --config /etc/pgdog/pgdog.toml --users /etc/pgdog/users.toml
```
Expected: PgDog starts and logs that it is listening on 6432. Backend connections will fail because those hostnames do not resolve — **that is fine and expected**. What matters is that it does not exit with a *config parse or validation* error. Give it ~10 seconds, then Ctrl-C.

- [ ] **Step 5: Deliberately break a key and confirm the error is distinguishable**

Change `role = "primary"` to `role = "leader"` in `scratch/pgdog.toml`, re-run the command from Step 4.
Expected: PgDog exits with a config error naming the bad value. This proves Step 4's success was real validation and not PgDog ignoring unknown keys. If PgDog *silently accepts* the bogus value, note that loudly in the reference doc — it means config typos will not be caught at boot and the renderer needs extra care. Revert the change afterwards.

- [ ] **Step 6: Iterate until the config is accepted**

For every key PgDog rejects, find the real spelling in `docker run --rm --entrypoint sh "${PGDOG_IMAGE}" -c 'ls /etc/pgdog 2>/dev/null; pgdog --help'`, in the container's bundled example config if one ships, or at `https://docs.pgdog.dev/configuration/`. Repeat Step 4 until clean.

- [ ] **Step 7: Record the verified format**

Write `docs/reference/pgdog-config.md` containing: the final working `pgdog.toml` and `users.toml` verbatim in fenced blocks, the exact image tag verified against, the CLI invocation, whether unknown keys are rejected (from Step 5), and a dated line stating this was verified empirically. Task 8 must treat this file — not this plan — as the source of truth for key names.

- [ ] **Step 8: Clean up and commit**

```bash
rm -rf scratch/
git add docs/reference/pgdog-config.md
git commit -m "docs: verify pgdog config format against pinned image"
```

**This completes Milestone 0.** All three of the spec's unverified assumptions are now settled facts.

---

## Task 5: CUE module, schemas, fabric, and the kind renderer

**Files:**
- Create: `cue.mod/module.cue`, `schema/topology.cue`, `schema/k8s.cue`, `schema/cnpg.cue`, `topology.cue`, `fabric.cue`, `render/kind.cue`
- Modify: `Justfile` (`render`, `check-render`, `fmt`, `vet` recipes)

**Interfaces:**
- Consumes: `kind.yaml` from Task 2 as the expected-output fixture.
- Produces: package `cnpgdog` exporting the top-level values `fabric` and `kindConfig`. `fabric.shards[i]` has fields `id` (int), `cluster` (string), `rw` (string), `ro` (string), `db` (string). `fabric.zones` is `[...string]`. Tasks 6, 7 and 8 consume `fabric` and must not re-derive any name.

- [ ] **Step 1: Initialise the CUE module**

```bash
nix develop -c cue mod init github.com/hsyed/cnpg-dog
```
Expected: `cue.mod/module.cue` created.

- [ ] **Step 2: Write `schema/topology.cue`**

```cue
package cnpgdog

// #Topology is the complete set of knobs for the fabric.
#Topology: {
	name:      string
	shards:    int & >=1
	zones:     [...string] & [_, ...] // at least one zone
	pgVersion: string
	storage:   string
}

// #Shard is a single derived shard. Every name in the system comes from here;
// nothing else may build a service name by concatenation.
#Shard: {
	id:      int & >=0
	cluster: string // CNPG Cluster metadata.name
	rw:      string // CNPG-owned primary service
	ro:      string // our read service, PreferSameZone
	db:      string // database name
}

// #ShardedTable is the one fact PgDog needs about the schema. It is consumed
// twice: by pgdog.toml and by the generated schema assertion.
#ShardedTable: {
	table:    string
	column:   string
	dataType: "bigint" | "uuid" | "text"
}

#Fabric: {
	topology: #Topology
	zones: [...string]
	shards: [...#Shard]
	shardedTables: [...#ShardedTable]
}
```

- [ ] **Step 3: Write `topology.cue` — the knobs**

```cue
package cnpgdog

topology: #Topology & {
	name:      "dog"
	shards:    4
	zones:     ["a", "b", "c"]
	pgVersion: "18"
	storage:   "1Gi"
}

shardedTables: [#ShardedTable & {
	table:    "events"
	column:   "tenant_id"
	dataType: "bigint"
}]
```

- [ ] **Step 4: Write `fabric.cue` — the single derivation**

```cue
package cnpgdog

import "list"

fabric: #Fabric & {
	topology:      _t
	zones:         _t.zones
	shardedTables: _st
	shards: [for i in list.Range(0, _t.shards, 1) {
		id:      i
		cluster: "\(_t.name)-s\(i)"
		rw:      "\(cluster)-rw"
		ro:      "\(cluster)-read"
		db:      _t.name
	}]
}

_t:  topology
_st: shardedTables
```

Note `ro` is `-read`, not CNPG's own `-ro`. We render that Service ourselves so we can set `trafficDistribution`, rather than depending on CNPG's managed-services API.

- [ ] **Step 5: Write the failing test — render the kind config and diff against the fixture**

Add to the `Justfile`:

```make
# Render CUE to plain YAML. PURE: touches no cluster, reads no environment.
render:
    mkdir -p rendered
    cue export -e kindConfig --out yaml . > rendered/kind.yaml

# Re-render and fail if committed output is stale, or if the kind fixture drifted
check-render: render
    diff -u kind.yaml rendered/kind.yaml
    git diff --exit-code -- rendered/

fmt:
    cue fmt ./...

vet:
    cue vet ./...
```

- [ ] **Step 6: Run it and watch it fail**

Run: `nix develop -c just render`
Expected: FAIL — `kindConfig` is not defined yet.

- [ ] **Step 7: Write `render/kind.cue`**

```cue
package cnpgdog

kindConfig: {
	kind:       "Cluster"
	apiVersion: "kind.x-k8s.io/v1alpha4"
	name:       "cnpg-dog"
	nodes: [{role: "control-plane"}] + [for z in fabric.zones {
		role: "worker"
		labels: "topology.kubernetes.io/zone": z
	}]
}
```

The worker list comes from `fabric.zones`, so a zone can never appear in a spread constraint without a node to satisfy it.

- [ ] **Step 8: Run render and the diff**

Run: `nix develop -c just check-render`
Expected: PASS — `rendered/kind.yaml` is byte-identical to the hand-written `kind.yaml`. If it differs only in key ordering or quoting, normalise both through `yq -P 'sort_keys(..)'` inside the `check-render` recipe rather than hand-editing the fixture to match the renderer.

- [ ] **Step 9: Write `schema/k8s.cue` and `schema/cnpg.cue`**

Partial, POC-grade definitions covering only the fields this project sets. Each file starts with this comment verbatim:

```cue
// POC-grade partial schema. Intentionally incomplete: it constrains only the
// fields this project sets. Authoritative validation is `kubectl apply
// --dry-run=server`. See the deviation note in the implementation plan.
```

`schema/k8s.cue` defines `#Meta` (name, namespace, optional labels and annotations), and `#ConfigMap`, `#Secret`, `#Service`, `#Deployment`, `#Namespace` each with `apiVersion`, `kind`, `metadata: #Meta`, and an open `spec`/`data` body. `schema/cnpg.cue` defines `#CNPGCluster` with `apiVersion: "postgresql.cnpg.io/v1"`, `kind: "Cluster"`, `metadata: #Meta`, and a `spec` carrying `instances: int`, `imageName: string`, `storage: size: string`, plus open fields for `bootstrap`, `postgresql` and `topologySpreadConstraints`. **Copy the `postgresql` field spellings from `docs/reference/cnpg-placement.md`, not from memory.**

- [ ] **Step 10: Run vet and fmt, then commit**

```bash
nix develop -c just fmt
nix develop -c just vet
nix develop -c just check-render
git add cue.mod schema topology.cue fabric.cue render/kind.cue rendered Justfile
git commit -m "feat: CUE topology model, fabric derivation, and kind renderer"
```

---

## Task 6: Render the CNPG shards and their read services

**Files:**
- Create: `render/namespace.cue`, `render/cnpg.cue`, `render/manifests.cue`
- Modify: `Justfile` (`render` emits the full manifest set)

**Interfaces:**
- Consumes: `fabric` from Task 5; verified field spellings from `docs/reference/cnpg-placement.md`.
- Produces: top-level `manifests` (a list of Kubernetes objects) and `secrets` (a separate list, never committed). `rendered/manifests.yaml` and `rendered-secrets/secrets.yaml`.

- [ ] **Step 1: Write the failing test — assert the rendered shape**

Add to the `Justfile`:

```make
render:
    mkdir -p rendered rendered-secrets
    cue export -e kindConfig --out yaml . > rendered/kind.yaml
    cue export -e manifests --out yaml . > rendered/manifests.yaml
    cue export -e secrets --out yaml . > rendered-secrets/secrets.yaml

# Structural assertions on rendered output. No cluster required.
check-manifests: render
    test "$(yq '. as $d | [$d.items[] | select(.kind == "Cluster")] | length' rendered/manifests.yaml)" = "4"
    for i in 0 1 2 3; do \
      yq -e ".items[] | select(.kind == \"Cluster\" and .metadata.name == \"dog-s$i\")" rendered/manifests.yaml > /dev/null; \
      yq -e ".items[] | select(.kind == \"Service\" and .metadata.name == \"dog-s$i-read\") | .spec.trafficDistribution == \"PreferSameZone\"" rendered/manifests.yaml > /dev/null; \
    done
    @echo "PASS: 4 shards, 4 read services with PreferSameZone"
```

- [ ] **Step 2: Run it and watch it fail**

Run: `nix develop -c just check-manifests`
Expected: FAIL — `manifests` is not defined.

- [ ] **Step 3: Write `render/namespace.cue`**

```cue
package cnpgdog

_namespace: #Namespace & {
	apiVersion: "v1"
	kind:       "Namespace"
	metadata: {
		name: fabric.topology.name
		annotations: "argocd.argoproj.io/sync-wave": "0"
	}
}

// App credentials. Rendered into the gitignored secrets stream, never committed.
_appSecret: #Secret & {
	apiVersion: "v1"
	kind:       "Secret"
	type:       "kubernetes.io/basic-auth"
	metadata: {
		name:      "\(fabric.topology.name)-app"
		namespace: fabric.topology.name
		annotations: "argocd.argoproj.io/sync-wave": "0"
	}
	stringData: {
		username: fabric.topology.name
		password: "dogpassword" // POC-grade. ExternalSecrets would replace this.
	}
}
```

- [ ] **Step 4: Write `render/cnpg.cue`**

Copy the `postgresql` block verbatim from `docs/reference/cnpg-placement.md`.

```cue
package cnpgdog

_clusters: [for s in fabric.shards {
	#CNPGCluster & {
		apiVersion: "postgresql.cnpg.io/v1"
		kind:       "Cluster"
		metadata: {
			name:      s.cluster
			namespace: fabric.topology.name
			annotations: "argocd.argoproj.io/sync-wave": "1"
		}
		spec: {
			instances: len(fabric.zones)
			imageName: "ghcr.io/cloudnative-pg/postgresql:\(fabric.topology.pgVersion)"
			storage: size: fabric.topology.storage
			bootstrap: initdb: {
				database: s.db
				owner:    s.db
				secret: name: "\(fabric.topology.name)-app"
			}
			postgresql: {
				synchronous: {
					method: "first"
					number: 1
				}
				syncReplicaElectionConstraint: {
					enabled: true
					nodeLabelsAntiAffinity: ["topology.kubernetes.io/zone"]
				}
			}
			topologySpreadConstraints: [{
				maxSkew:           1
				topologyKey:       "topology.kubernetes.io/zone"
				whenUnsatisfiable: "DoNotSchedule"
				labelSelector: matchLabels: "cnpg.io/cluster": s.cluster
			}]
		}
	}
}]

// Read services we own, so we can set trafficDistribution ourselves rather
// than depending on CNPG's managed-services API. The replica label key is the
// one verified in docs/reference/cnpg-placement.md.
_readServices: [for s in fabric.shards {
	#Service & {
		apiVersion: "v1"
		kind:       "Service"
		metadata: {
			name:      s.ro
			namespace: fabric.topology.name
			annotations: "argocd.argoproj.io/sync-wave": "1"
		}
		spec: {
			type:                "ClusterIP"
			trafficDistribution: "PreferSameZone"
			selector: {
				"cnpg.io/cluster":      s.cluster
				"cnpg.io/instanceRole": "replica"
			}
			ports: [{
				name:       "postgres"
				port:       5432
				targetPort: 5432
			}]
		}
	}
}]
```

- [ ] **Step 5: Write `render/manifests.cue`**

```cue
package cnpgdog

// Applied output, safe to commit.
manifests: {
	apiVersion: "v1"
	kind:       "List"
	items:      [_namespace] + _clusters + _readServices
}

// Gitignored. Applied but never committed.
secrets: {
	apiVersion: "v1"
	kind:       "List"
	items: [_appSecret]
}
```

- [ ] **Step 6: Run the structural test**

Run: `nix develop -c just check-manifests`
Expected: PASS — four `Cluster` objects named `dog-s0`..`dog-s3`, four read Services with `PreferSameZone`.

- [ ] **Step 7: Validate against the real API server**

Run:
```bash
nix develop -c bash -c '
  kubectl apply --server-side --dry-run=server -f rendered/manifests.yaml
  kubectl apply --server-side --dry-run=server -f rendered-secrets/secrets.yaml'
```
Expected: every object accepted. This is the authoritative schema gate. Any rejection means a field spelling is wrong — fix it in the CUE and re-run, and correct `docs/reference/cnpg-placement.md` if it was the source of the error.

- [ ] **Step 8: Commit**

```bash
git add render Justfile rendered
git commit -m "feat: render CNPG shard clusters and zone-aware read services"
```

---

## Task 7: Apply the shards and assert real zone placement

**Files:**
- Create: `scripts/check-placement.sh`
- Modify: `Justfile` (`apply`, `wait`, `check` recipes)

**Interfaces:**
- Consumes: `rendered/manifests.yaml`, `rendered-secrets/secrets.yaml`.
- Produces: `scripts/check-placement.sh`, exit 0 on success. Four healthy CNPG clusters. **Milestone 2 gate.**

- [ ] **Step 1: Write the `apply` and `wait` recipes**

```make
# Apply rendered manifests, wave by wave
apply: render
    kubectl apply --server-side -f rendered-secrets/secrets.yaml
    kubectl apply --server-side -f rendered/manifests.yaml
    just wait

wait:
    kubectl -n "${APP_NS}" wait --for=condition=Ready cluster --all --timeout=600s
```

If Task 3 recorded a readiness condition other than `Ready`, use that one here.

- [ ] **Step 2: Write the failing placement test**

`scripts/check-placement.sh`:

```bash
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
```

- [ ] **Step 3: Run it before applying, to confirm it can fail**

Run: `nix develop -c bash scripts/check-placement.sh`
Expected: no clusters found, script exits 0 with no output. Confirm the loop body is genuinely reached later — this step only proves the script runs.

- [ ] **Step 4: Apply for real**

Run: `nix develop -c just apply`
Expected: 12 Postgres pods reach Ready within the timeout. This takes several minutes on first run because every pod pulls the Postgres image. If pods sit `Pending` on `DoNotSchedule`, check that `kubectl get nodes -L topology.kubernetes.io/zone` still shows three zones.

- [ ] **Step 5: Run the placement assertions**

Run: `nix develop -c bash scripts/check-placement.sh`
Expected: eight PASS lines — one spread and one sync-replica line per shard — and exit 0.

- [ ] **Step 6: Wire it into `check` and commit**

```make
check:
    bash scripts/check-placement.sh
```

```bash
chmod +x scripts/check-placement.sh
git add scripts/check-placement.sh Justfile
git commit -m "feat: apply CNPG shards and assert per-zone placement"
```

**This completes Milestone 2.**

---

## Task 8: Render and deploy PgDog

**Files:**
- Create: `render/pgdog.cue`
- Modify: `render/manifests.cue` (append PgDog objects)

**Interfaces:**
- Consumes: `fabric`, and **`docs/reference/pgdog-config.md` as the authoritative source for every TOML key name**. If this plan's key names disagree with that file, the file wins.
- Produces: PgDog ConfigMap, Deployment and Service in namespace `dog`; `pgdog:6432` reachable in-cluster.

- [ ] **Step 1: Write the failing test**

Add to the `Justfile`:

```make
check-pgdog-config: render
    yq -r '.items[] | select(.kind == "ConfigMap" and .metadata.name == "pgdog") | .data["pgdog.toml"]' \
      rendered/manifests.yaml | tee /tmp/pgdog-rendered.toml
    test "$(grep -c '^\[\[databases\]\]' /tmp/pgdog-rendered.toml)" = "8"
    grep -q 'shard = 3' /tmp/pgdog-rendered.toml
    grep -q 'host = "dog-s3-read"' /tmp/pgdog-rendered.toml
    @echo "PASS: 8 database entries (4 shards x primary+replica)"
```

- [ ] **Step 2: Run it and watch it fail**

Run: `nix develop -c just check-pgdog-config`
Expected: FAIL — no ConfigMap named `pgdog`.

- [ ] **Step 3: Write `render/pgdog.cue`**

```cue
package cnpgdog

import "encoding/toml"

_pgdogConfig: {
	general: {
		host:              "0.0.0.0"
		port:              6432
		workers:           2
		default_pool_size: 10
	}
	databases: [for s in fabric.shards for e in [
		{name: s.db, host: s.rw, port: 5432, role: "primary", shard: s.id, database_name: s.db},
		{name: s.db, host: s.ro, port: 5432, role: "replica", shard: s.id, database_name: s.db},
	] {e}]
	sharded_tables: [for t in fabric.shardedTables {
		database:  fabric.topology.name
		table:     t.table
		column:    t.column
		data_type: t.dataType
	}]
}

_pgdogUsers: users: [{
	name:     fabric.topology.name
	database: fabric.topology.name
	password: "dogpassword"
}]

_pgdogConfigMap: #ConfigMap & {
	apiVersion: "v1"
	kind:       "ConfigMap"
	metadata: {
		name:      "pgdog"
		namespace: fabric.topology.name
		annotations: "argocd.argoproj.io/sync-wave": "2"
	}
	data: "pgdog.toml": toml.Marshal(_pgdogConfig)
}

_pgdogSecret: #Secret & {
	apiVersion: "v1"
	kind:       "Secret"
	metadata: {
		name:      "pgdog-users"
		namespace: fabric.topology.name
		annotations: "argocd.argoproj.io/sync-wave": "0"
	}
	stringData: "users.toml": toml.Marshal(_pgdogUsers)
}

_pgdogDeployment: #Deployment & {
	apiVersion: "apps/v1"
	kind:       "Deployment"
	metadata: {
		name:      "pgdog"
		namespace: fabric.topology.name
		annotations: "argocd.argoproj.io/sync-wave": "2"
	}
	spec: {
		replicas: len(fabric.zones)
		selector: matchLabels: app: "pgdog"
		template: {
			metadata: labels: app: "pgdog"
			spec: {
				topologySpreadConstraints: [{
					maxSkew:           1
					topologyKey:       "topology.kubernetes.io/zone"
					whenUnsatisfiable: "DoNotSchedule"
					labelSelector: matchLabels: app: "pgdog"
				}]
				containers: [{
					name:  "pgdog"
					image: "ghcr.io/pgdogdev/pgdog:v0.1.53"
					args: ["--config", "/etc/pgdog/pgdog.toml", "--users", "/etc/pgdog/users.toml"]
					ports: [{containerPort: 6432, name: "pgdog"}]
					volumeMounts: [
						{name: "config", mountPath: "/etc/pgdog/pgdog.toml", subPath: "pgdog.toml"},
						{name: "users", mountPath: "/etc/pgdog/users.toml", subPath: "users.toml"},
					]
				}]
				volumes: [
					{name: "config", configMap: name: "pgdog"},
					{name: "users", secret: secretName: "pgdog-users"},
				]
			}
		}
	}
}

_pgdogService: #Service & {
	apiVersion: "v1"
	kind:       "Service"
	metadata: {
		name:      "pgdog"
		namespace: fabric.topology.name
		annotations: "argocd.argoproj.io/sync-wave": "2"
	}
	spec: {
		type: "ClusterIP"
		selector: app: "pgdog"
		ports: [{name: "pgdog", port: 6432, targetPort: 6432}]
	}
}
```

The PgDog image tag appears here as a literal, which violates the "versions live only in `flake.nix`" constraint. Resolve it by having the `render` recipe pass the value in: `cue export -e manifests --out yaml -t pgdogImage="${PGDOG_IMAGE}" .` with `image: string @tag(pgdogImage)` in the CUE. Do this — do not leave the literal.

- [ ] **Step 4: Run the config test**

Run: `nix develop -c just check-pgdog-config`
Expected: PASS — eight `[[databases]]` entries, `shard = 3` present, `host = "dog-s3-read"` present. Compare the emitted TOML against `docs/reference/pgdog-config.md` line by line; any key-name difference is a bug in the renderer, not in the reference.

- [ ] **Step 5: Add PgDog to the manifest lists**

In `render/manifests.cue`, change `items` to `[_namespace] + _clusters + _readServices + [_pgdogConfigMap, _pgdogDeployment, _pgdogService]`, and the secrets list to `[_appSecret, _pgdogSecret]`.

- [ ] **Step 6: Dry-run, apply, and confirm PgDog is serving**

```bash
nix develop -c bash -c '
  kubectl apply --server-side --dry-run=server -f rendered/manifests.yaml
  just apply
  kubectl -n "${APP_NS}" rollout status deployment/pgdog --timeout=180s
  kubectl -n "${APP_NS}" logs deployment/pgdog --tail=30'
```
Expected: three PgDog pods running, one per zone, logs showing it listening on 6432 with no config errors.

- [ ] **Step 7: Commit**

```bash
git add render Justfile rendered
git commit -m "feat: render and deploy pgdog with fabric-derived routing table"
```

---

## Task 9: Schema, seed, and the generated schema assertion

**Files:**
- Create: `sql/schema.sql`, `sql/seed.sql`, `render/sql.cue`
- Modify: `Justfile` (`seed` recipe)

**Interfaces:**
- Consumes: `fabric.shardedTables`, a running PgDog.
- Produces: `rendered/assert_schema.sql`; a seeded `events` table reachable through PgDog.

- [ ] **Step 1: Write `sql/schema.sql` by hand**

```sql
CREATE TABLE IF NOT EXISTS events (
    id        BIGSERIAL,
    tenant_id BIGINT NOT NULL,
    payload   TEXT   NOT NULL,
    PRIMARY KEY (id, tenant_id)
);
```

- [ ] **Step 2: Write `render/sql.cue` — generate the drift assertion**

```cue
package cnpgdog

assertSchema: {
	_lines: [for t in fabric.shardedTables {
		"""
		DO $$ BEGIN
		  IF NOT EXISTS (
		    SELECT 1 FROM information_schema.columns
		    WHERE table_name = '\(t.table)'
		      AND column_name = '\(t.column)'
		      AND data_type = '\(t.dataType)'
		  ) THEN
		    RAISE EXCEPTION 'sharding key \(t.table).\(t.column) is not \(t.dataType)';
		  END IF;
		END $$;
		"""
	}]
	out: _lines
}
```

Export it as text in the `render` recipe: `cue export -e 'assertSchema.out' --out text . > rendered/assert_schema.sql` — if `--out text` rejects a list, join the list in CUE with `strings.Join(_lines, "\n")` and export that string instead.

- [ ] **Step 3: Write `sql/seed.sql`**

Seed 400 rows across 40 tenant ids, so every shard should receive some.

```sql
INSERT INTO events (tenant_id, payload)
SELECT (g % 40) + 1, 'payload-' || g
FROM generate_series(1, 400) g;
```

- [ ] **Step 4: Write the `seed` recipe**

```make
seed: render
    kubectl -n "${APP_NS}" exec deployment/pgdog -- true  # ensure pod exists
    kubectl -n "${APP_NS}" run psql-probe --rm -i --restart=Never \
      --image="${PG_IMAGE}" --env=PGPASSWORD=dogpassword -- \
      psql -h pgdog -p 6432 -U dog -d dog -v ON_ERROR_STOP=1 -f - < sql/schema.sql
    kubectl -n "${APP_NS}" run psql-probe --rm -i --restart=Never \
      --image="${PG_IMAGE}" --env=PGPASSWORD=dogpassword -- \
      psql -h pgdog -p 6432 -U dog -d dog -v ON_ERROR_STOP=1 -f - < rendered/assert_schema.sql
    kubectl -n "${APP_NS}" run psql-probe --rm -i --restart=Never \
      --image="${PG_IMAGE}" --env=PGPASSWORD=dogpassword -- \
      psql -h pgdog -p 6432 -U dog -d dog -v ON_ERROR_STOP=1 -f - < sql/seed.sql
```

- [ ] **Step 5: Run it**

Run: `nix develop -c just seed`
Expected: DDL applies across all shards, the assertion passes silently, 400 rows insert. If DDL does not reach every shard, check PgDog's cross-shard DDL behaviour in its docs and — if it does not broadcast — apply `sql/schema.sql` directly to each `dog-sN-rw` in a loop instead, recording the reason in `README.md`.

- [ ] **Step 6: Prove the assertion actually fires**

Temporarily change `dataType` in `topology.cue` to `"text"`, run `just render && just seed`.
Expected: the assertion raises `sharding key events.tenant_id is not text`. Revert the change afterwards. Without this step the assertion is untested and may be vacuous.

- [ ] **Step 7: Commit**

```bash
git add sql render/sql.cue Justfile rendered
git commit -m "feat: sharded schema, seed data, and generated drift assertion"
```

---

## Task 10: Routing assertions and the full acceptance run

**Files:**
- Create: `scripts/check-routing.sh`
- Modify: `Justfile` (`check` recipe), `README.md`

**Interfaces:**
- Consumes: everything above.
- Produces: **the Milestone 3 gate and the spec §1 acceptance criteria.**

- [ ] **Step 1: Write `scripts/check-routing.sh`**

```bash
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

# 3. Reachability: every seeded tenant retrievable through pgdog.
found=$(kubectl -n "$ns" run psql-probe-check --rm -i --restart=Never -q \
  --image="${PG_IMAGE}" --env=PGPASSWORD=dogpassword -- \
  psql -h pgdog -p 6432 -U dog -d dog -Atc "select count(distinct tenant_id) from events" | tr -d '\r')
if [ "$found" != "40" ]; then
  echo "FAIL: pgdog sees $found distinct tenants, expected 40"; fail=1
else echo "PASS: all 40 tenants reachable through pgdog"; fi

exit $fail
```

Deliberately **not** asserted: an exact tenant-to-shard mapping. That would mean reimplementing PgDog's hash function in the test (spec §6.4).

- [ ] **Step 2: Run it**

Run: `nix develop -c bash scripts/check-routing.sh`
Expected: three PASS lines, exit 0. If assertion 2 fails with everything on one shard, PgDog is not sharding — check that `[[sharded_tables]]` reached the ConfigMap and that the table name matches.

- [ ] **Step 3: Wire the full `check` recipe**

```make
check: check-render check-manifests check-pgdog-config
    bash scripts/check-placement.sh
    bash scripts/check-routing.sh
    @echo "ALL CHECKS PASSED"
```

- [ ] **Step 4: Run the complete acceptance sequence from scratch**

This is the spec §1 acceptance criterion. It must pass with no manual intervention.

```bash
nix develop -c bash -c 'just down || true'
nix develop -c just up
nix develop -c just apply
nix develop -c just seed
nix develop -c just check
```
Expected: `ALL CHECKS PASSED`. Any manual `kubectl` needed along the way is a bug in the Justfile — fix it and rerun the whole sequence from `just down`.

- [ ] **Step 5: Run it a second time to prove reproducibility**

Run the exact same five commands again.
Expected: `ALL CHECKS PASSED`. A first-run-only success is not a result — it means something depended on leftover state.

- [ ] **Step 6: Update `README.md` and commit**

Record: the verified acceptance sequence, approximate wall-clock time for `just up && just apply`, and any deviations from this plan discovered along the way (particularly Task 3 and Task 4 findings).

```bash
chmod +x scripts/check-routing.sh
git add scripts/check-routing.sh Justfile README.md
git commit -m "feat: routing assertions and full acceptance run"
```

**This completes Milestones 3 and the spec's acceptance criteria.**

---

## Self-Review Notes

**Spec coverage.** §1 goals: wiring (Tasks 8–10), config architecture (Tasks 5–6), multi-zone (Tasks 2, 3, 7), reproducibility (Task 1, Task 10 Step 5). §1 acceptance criteria: Task 10 Steps 4–5 verbatim. §3 three-layer architecture: Task 5. §4 cluster topology: Tasks 6–8. §5 repo layout and Justfile: Tasks 1, 5–10. §6 verification — `cue vet` (Task 5 Step 10, with the recorded deviation), render determinism (Task 5, `check-render`), placement (Task 7), routing (Task 10), schema contract (Task 9). §7 Argo readiness: sync-wave annotations in Tasks 6 and 8, `rendered/` committed from Task 5. §8 deferred work: correctly absent, seams preserved by the `#Shard` and `zones` structure. §9 risks: Task 3 settles the CNPG unknowns, Task 4 the PgDog unknowns, Task 1 the `trafficDistribution` floor, Task 5 Step 9 the schema-vendoring fallback.

**Known soft spots the executor should expect to fix rather than work around.** Task 5 Step 8 may need YAML normalisation before the kind fixture diff is clean. Task 9 Step 2's `--out text` on a list may need `strings.Join`. Task 9 Step 5 assumes PgDog broadcasts DDL cross-shard; the fallback is spelled out. Task 8 Step 3's image literal must be converted to a `@tag` injection, which is stated as a requirement rather than left as debt.
