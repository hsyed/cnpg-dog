# CNPG + PgDog POC — Design

**Date:** 2026-08-15
**Status:** Approved for planning

## 1. Purpose

Prove out a cloud-native Postgres fabric where [CloudNativePG](https://cloudnative-pg.io/)
manages the shards and [PgDog](https://pgdog.dev/) provides sharded routing in front of
them, with the entire topology encoded in CUE.

The primary *intellectual* deliverable is *the shape of the configuration model*.
The primary *physical* deliverable is **a running `kind` cluster**. Neither
substitutes for the other: a beautiful model that has never been applied is not a
result, and the model is only judged good if the cluster it produces actually
comes up.

### Acceptance criteria

The POC is done when, from a clean checkout on a machine with Nix:

```
nix develop -c just up      # kind cluster, zone-labeled nodes, CNPG operator
nix develop -c just apply   # rendered manifests, wave by wave
nix develop -c just seed
nix develop -c just check   # all assertions in §6 green
```

...succeeds end to end with no manual intervention, leaving a live cluster in which:

- 4 CNPG shards are `Cluster` phase healthy, 3 instances each, one instance per
  simulated zone;
- PgDog is serving on `:6432` and `psql` through it can write and read;
- seeded rows are verifiably partitioned across shards (§6.4);
- `just down && just up && just apply && just check` passes again — teardown and
  recreate is reproducible, not a one-time lucky boot.

Rendered YAML that has never been applied does not satisfy any of the above.
Milestones 2 and 3 (§10) are each gated on a live, healthy cluster.

### Goals

1. **Wiring.** CNPG-managed shards behind PgDog, sharded writes partitioned across
   shards, reachable through the proxy.
2. **Config architecture.** One CUE topology value; adding a shard is a one-number
   change; the routing table cannot drift from the clusters that exist.
3. **Multi-zone.** Shard instances spread one per simulated zone, sync replica
   elected cross-zone, and a zone-local read path.
4. **Reproducibility.** A Nix flake pins every tool and image version so the
   implementing agent's environment matches the author's.

### Non-goals

Day-2 operations are explicitly **out of scope for implementation**: adding a shard
at runtime, resharding with data movement, and failover demonstrations are not
built. They must, however, remain *expressible* in the model — §8 records where each
would attach.

Argo CD is not installed. The design is constrained so that adopting it later is
additive rather than a rewrite (§7).

## 2. Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Config language | CUE | User's choice; supersedes an initial Tanka/jsonnet idea. |
| Render/apply path | Plain CUE module, `cue export` piped to `kubectl apply` | Keeps the whole topology in one type-checked value. Timoni was considered and rejected: it owns the apply path, which duplicates Argo's job and adds a second contract to learn on top of the subject under study. Rendering values for the upstream PgDog Helm chart was rejected because CUE's type checking would stop at the chart boundary, undercutting the central claim. |
| GitOps | Argo-ready, not Argo-installed | Ordering encoded as sync-wave annotations; `rendered/` is a valid Argo Application source on day one. |
| Zone model | Placement **plus** zone-local reads | Uses stock Kubernetes locality (`trafficDistribution: PreferSameZone`) rather than bespoke per-zone proxy configs. |
| Command runner | `just` | Owns the verbs; the flake owns the binaries. No overlap. |
| Sharded schema | Plain SQL DDL, sharding contract in CUE | Avoids a DDL generator while preserving the one-fact property, via a generated assertion (§6). |
| Operator install | Pinned upstream release URL, applied by `just` | A ~6000-line vendor artifact is not worth modelling in CUE. |

## 3. Architecture

Three layers, each a pure function of the previous one.

```
shardedCluster.cue  the knobs — the only file edited day to day
      |
      v
fabric.cue        every name and endpoint, derived exactly once
      |
      +--> lib/cnpg.cue    Cluster CRs + read Services
      +--> lib/pgdog.cue   ConfigMap(pgdog.toml) + Deployment + Service
      +--> lib/kind.cue    kind cluster config with zone labels
```

### The central claim

PgDog's routing table and the CNPG clusters are not two configurations that agree
with each other. They are one value read twice. The host string in
`[[databases]]` is the *same CUE expression* as the service name derived from the
`Cluster` CR's name. Changing `shards: 4` to `shards: 8` cannot produce a PgDog
that points at a cluster which does not exist — not by convention, by unification.

This claim is falsifiable in roughly 200 lines of CUE, which is the point of the
POC.

### Layer 1 — shardedCluster

```cue
shardedCluster: #ShardedCluster & {
    name:      "dog"
    shards:    4
    pgVersion: "18"
    storage:   "1Gi"
    tables: [#ShardedTable & {
        table:    "events"
        column:   "tenant_id"
        dataType: "bigint"
    }, #ShardedTable & {
        table:    "orders"
        column:   "tenant_id"
        dataType: "bigint"
    }]
}
```

### Layer 2 — fabric

Derives the names. Nothing else in the repo constructs a service name by string
concatenation. Placement (`zones`) is not part of the fabric — it lives in the
render layer.

```cue
fabric: #Fabric & {
    _t: shardedCluster
    shards: [for i in list.Range(0, _t.shards, 1) {
        id:      i
        cluster: "\(_t.name)-s\(i)"   // CNPG Cluster metadata.name
        rw:      "\(cluster)-rw"      // CNPG-owned primary service
        ro:      "\(cluster)-ro"      // read path, PreferSameZone
        db:      _t.name
    }]
}
```

### Layer 3 — renderers

`lib/cnpg.cue` emits, per shard:

- a `postgresql.cnpg.io/v1` `Cluster` with `instances: len(zones)`,
- `spec.topologySpreadConstraints` on `topology.kubernetes.io/zone`, `maxSkew: 1`,
  `whenUnsatisfiable: DoNotSchedule`,
- `spec.postgresql.syncReplicaElectionConstraint` with
  `nodeLabelsAntiAffinity: ["topology.kubernetes.io/zone"]`, so the sync replica is
  elected outside the primary's zone,
- a read `Service` carrying `spec.trafficDistribution: PreferSameZone`.

`lib/pgdog.cue` emits `[[databases]]` — per shard, one `primary` entry pointing
at `shards[i].rw` and one `replica` entry pointing at `shards[i].ro`, both stamped
with `shard = i` — plus `[[sharded_tables]]` from the schema contract. The whole
structure is marshalled with CUE's `encoding/toml` into a ConfigMap, alongside a
zone-spread PgDog Deployment and its Service.

## 4. Cluster topology

```
kind: 1 control-plane + 3 workers, labeled topology.kubernetes.io/zone = a|b|c
|
+-- cnpg-system   CNPG operator, applied from pinned release URL
|
+-- dog
    +-- dog-s0..s3   Cluster CR, 3 instances, one per zone
    |                  -> dog-sN-rw, dog-sN-ro (PreferSameZone)
    +-- pgdog          Deployment, 3 replicas, zone-spread
    |                    ConfigMap: pgdog.toml   (rendered)
    |                    Secret:    users.toml   (rendered, gitignored)
    |                    Service:   pgdog:6432
    +-- psql-probe     sleeping pod for manual inspection
```

Ordering is expressed as `argocd.argoproj.io/sync-wave` annotations — secrets `0`,
clusters `1`, PgDog `2` — so it transfers to Argo unchanged. Locally, `just` performs
the equivalent `kubectl wait` between waves.

## 5. Repository layout

```
flake.nix              devShell + pinned versions (single home for all versions)
Justfile               the verbs
cue.mod/
  module.cue
  gen/                 vendored k8s + CNPG schemas
shardedCluster.cue     the knobs (shardedCluster + its tables subsection)
lib/
  fabric.cue           #ShardedCluster/#ShardedTable/#Shard/#Fabric + derivation
  schema.cue           POC-grade k8s + CNPG partial schemas
render/
  zones.cue            placement (availability zones)
  cnpg.cue             Cluster CRs + read Services
  pgdog.cue            ConfigMap(pgdog.toml) + Deployment + Service
  kind.cue             kind cluster config
  namespace.cue        Namespace + app credentials Secret
  manifests.cue        top-level export, sync-wave annotated
  sql.cue              generated schema assertion
sql/
  schema.sql           hand-written DDL
  seed.sql             hand-written seed data
rendered/              committed golden output; also a valid Argo source
docs/superpowers/specs/
```

### Justfile recipes

```
just up            kind create + zone labels + pinned CNPG operator + wait
just render        cue export -e manifests --out yaml > rendered/   (pure)
just apply         kubectl apply --server-side -f rendered/, wave by wave
just wait          kubectl wait cluster/dog-s* + rollout status pgdog
just seed          psql through pgdog, apply sql/schema.sql
just check         placement + routing + schema assertions
just check-render  re-render and fail on a dirty diff
just psql          shell against the pgdog service
just diff          cue export | kubectl diff -f -
just fmt / vet     cue fmt / cue vet against vendored schemas
just down          kind delete cluster
```

**`render` and `apply` must stay separate verbs.** `render` touches no cluster and
reads no environment; it is the pure function Argo would call. `apply` is the only
impure recipe. This split is what prevents cluster-awareness from leaking into the
renderer and quietly killing the GitOps path.

### Flake contents

`cue`, `kubectl`, `kind`, `just`, `postgresql` (for `psql`), `jq`, and the `cnpg`
kubectl plugin. Version pins with exactly one home each: the **kind node image tag**
(must be recent enough for `trafficDistribution`), the **CNPG operator release URL**,
and the **PgDog image tag**.

## 6. Verification

Four checks, cheapest first. All are wired into `just check` except `check-render`.

1. **`cue vet`** against the vendored k8s and CNPG schemas. Malformed resources fail
   before anything touches a cluster.
2. **Render determinism.** `rendered/` is committed; `just check-render` re-renders
   and fails on a dirty diff. Costs nothing and doubles as the Argo source.
3. **Placement.** Assert each shard has exactly one instance per zone, and that the
   elected sync replica is outside the primary's zone. This is the only check that
   verifies the multi-zone claim rather than merely configuring it.
4. **Routing.** Seed rows with known sharding keys through PgDog, then connect
   *directly* to each `dog-sN-rw`, bypassing the proxy, and count. Assert: the total
   across shards equals the number seeded; no single shard holds all of them; every
   seeded key is retrievable through PgDog.

   Deliberately **not** asserted: an exact key-to-shard mapping. Doing so would mean
   reimplementing PgDog's hash function in the test. The property that matters is
   "partitioned, complete, and reachable", which the three assertions above capture.

### Schema contract

`sql/schema.sql` is hand-written DDL. CUE holds only the fact PgDog needs:

```cue
#ShardedTable: {
    table:    string
    column:   string
    dataType: "bigint" | "uuid" | "varchar" | "vector"
}
```

`shardedCluster.tables` is a list, and the POC demonstrates it with two tables
(`events`, `orders`) sharing the `tenant_id` convention, so the comprehension
that renders `[[sharded_tables]]` is exercised as a list rather than a
list-of-one. This renders into `[[sharded_tables]]` and, to prevent drift from
the DDL, also renders `rendered/assert_schema.sql` — a query against
`information_schema.columns` that fails if the real column type differs from what
PgDog was told. One fact, two consumers, no DDL generator.

## 7. Argo CD readiness

Not installed, but unblocked. Three properties make adoption additive:

- `rendered/` is plain YAML in git — a valid Application source using the
  rendered-manifests pattern, with no config-management plugin required.
- Ordering lives in sync-wave annotations on the resources themselves, not in the
  Justfile.
- Argo ships an upstream health check for `postgresql.cnpg.io/Cluster`, so it will
  correctly wait on shard readiness.

A CMP sidecar carrying the `cue` binary remains available as an alternative if live
rendering is wanted later.

## 8. Deferred work and its attachment points

| Deferred | Where it attaches |
|---|---|
| Add a shard at runtime | Already a one-number change in `shardedCluster.cue`; needs schema application to the new shard and a PgDog config reload. |
| Resharding with data movement | A key-range field on `#Shard`; PgDog's logical-replication resharding is the mechanism. Note that hash sharding remaps most rows on an N to N+1 change, so this is a prerequisite for an honest rebalance. |
| Failover demonstration | No model change; CNPG promotes and the `-rw` service follows. |
| Zonal front doors | A comprehension over `zones` in `lib/pgdog.cue`, plus a zone-pinned Service per shard. |
| ExternalSecrets | The secrets seam in `lib/pgdog.cue`; PgDog's Helm chart models this as `usersSecret.name` / `configSecret.name` and is worth mirroring. |
| Observability | PgDog exposes an OpenMetrics endpoint; a ServiceMonitor would slot into `lib/pgdog.cue`. |

## 9. Risks and uncertainties

**PgDog's exact TOML keys are unverified.** The concepts are confirmed from PgDog's
documentation — `pgdog.toml` and `users.toml` as separate files, `[[databases]]`
entries carrying host/role/shard, `[[sharded_tables]]` carrying column and data type
— but the precise key spellings for the pinned version are not. **Milestone 0
therefore requires pinning a PgDog image tag and validating a hand-written
`pgdog.toml` against it before any renderer is written.** Building the generator
against a guess is the single most likely way to waste a day.

**CUE's TOML encoding is marked experimental.** `--out toml` and `encoding/toml`'s
`Marshal` exist and are documented, but if the API proves unstable, the fallback is
to render the ConfigMap value from a CUE string template — ugly, but contained to
one file.

**CNPG CRD schema vendoring.** Generating full CUE definitions from the CNPG CRD is
the ideal. If that proves awkward, hand-writing a partial `#Cluster` definition
covering only the fields used is an acceptable POC-grade substitute, and should be
labelled as such in a comment.

**`trafficDistribution: PreferSameZone` requires a recent Kubernetes.** The kind node
image tag must be chosen accordingly and pinned in the flake. If the field is
unavailable, the fallback is the older topology-aware-hints annotation, with the
zone-local read claim downgraded to best-effort.

**Secrets are the weakest part of the design.** A pinned password Secret, rendered
but gitignored, is POC-grade only. The ExternalSecrets shape is noted where it would
slot in.

## 10. Implementation milestones

Each milestone is gated on running code, not on files existing. A milestone with
unapplied manifests is not complete.

0. **Foundation.** Flake, kind cluster with zone labels, CNPG operator installed.
   *Gate:* `kind` cluster is up, `kubectl get nodes -L topology.kubernetes.io/zone`
   shows three distinct zones, operator pod is `Running`, and a hand-written
   `pgdog.toml` has been validated against the pinned PgDog image. No CUE renderers
   yet.
1. **Model.** `shardedCluster.cue`, `zones.cue`, and the `lib/` package.
   *Gate:* `cue vet` passes and `just render` produces committed golden output.
   This is the one milestone with no live-cluster gate, because it produces no
   cluster state of its own.
2. **Shards.** *Gate:* CNPG clusters applied and reporting healthy in a live
   cluster; placement assertions (§6.3) pass against real pod placement.
3. **Proxy.** *Gate:* PgDog applied and serving; seed and routing assertions (§6.4)
   pass; the full acceptance sequence in §1 runs clean from `just down`.
