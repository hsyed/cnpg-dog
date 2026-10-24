# CNPG + PgDog Sharding POC

A cloud-native Postgres deployment where [CloudNativePG](https://cloudnative-pg.io/)
manages the shards and [PgDog](https://pgdog.dev/) provides sharded routing in
front of them, with the entire topology encoded in CUE. See
`docs/superpowers/specs/2026-08-15-cnpg-pgdog-poc-design.md` for the design and
`docs/superpowers/plans/2026-08-15-cnpg-pgdog-poc.md` for the implementation plan.

Every version pin (kind node image, CNPG operator release, PgDog image,
Postgres image) lives in `flake.nix` and nowhere else. The devShell exports
them as environment variables that the Justfile recipes read.

## Running

```bash
nix develop
just up && just apply && just seed && just check
```

`just up` and `just apply` together take ~5 minutes on first run (image pulls);
a warm run is ~2 minutes.

## Acceptance

The spec §1 criterion is the full sequence from scratch, run twice:

```bash
just down || true
just up
just apply
just seed
just check   # expects "ALL CHECKS PASSED"
```

`just check` runs six gates: render determinism (`check-render`), manifest
shape (`check-manifests`), the rendered PgDog routing table
(`check-pgdog-config`), topology fixtures (`check-topology`),
placement (`scripts/check-placement.sh`), and
partition/completeness/reachability (`scripts/check-routing.sh`).

## Configuration

Edit `topology.cue`. The POC explicitly selects four shards; the schema defaults
to **one shard of the same topology**. There is no separate unsharded mode.
`pg.template.spec.instances` is the native total PostgreSQL instance count per
shard, including the primary; `dog.replicas` is the independent total proxy count.

```cue
topology: topologyTypes.#Topology & {
    name: "dog"
    pg: {
        shards:   1 // Default; the routing model is identical at every count.
        template: {
            // Native CNPG Cluster fields, validated against the pinned CRD.
            metadata: labels: team: "platform"
            spec: {
                instances: 3 // Includes the primary; defaults to 3.
                imageName: "ghcr.io/cloudnative-pg/postgresql:18"
                storage: size: "32Gi"
                resources: {
                    requests: {cpu: "500m", memory: "1Gi"}
                    limits: memory: "2Gi"
                }
                affinity: {
                    topologyKey:         "topology.kubernetes.io/zone"
                    podAntiAffinityType: "required"
                }
                postgresql: synchronous: {
                    method:         "any"
                    number:         1
                    dataDurability: "required"
                }
            }
        }
    }
    dog: {
        replicas: 3 // Total proxy pods, not per shard; defaults to 3.
        resources: {
            requests: {cpu: "250m", memory: "128Mi"}
            limits: memory: "512Mi"
        }
        // Optional affinity uses Kubernetes Affinity.
        // Define routing from day one, even with a single shard.
        shardedColumns: [{column: "tenant_id", dataType: "bigint"}]
    }
}
```

These resource quantities and policies are examples, not wrapper defaults.
The renderer adds no affinity, spread constraints, or replication policy:
CNPG's native defaults apply to omitted fields. PgDog's optional `affinity`,
`topologySpreadConstraints`, and `resources` use native Kubernetes types.

`pg.template` is a native `Cluster` manifest, not a second configuration surface.
The wrapper supplies `apiVersion`, `kind`, shard name, namespace, and sync-wave.
`template.spec.instances` is the only database instance count; there is no
wrapper-level replica alias. Spec fields pass through, including native storage,
placement, PostgreSQL parameters, durability/failover policy, and update strategy.
The default bootstrap creates the database/user named by `topology.name`.
An explicit native `bootstrap` is preserved instead; you are responsible for
matching its database, user, and credentials to PgDog.

### Singleton and growth

Shard zero is always `name-s0`, with the same primary/read endpoints and PgDog
`shard = 0` metadata used in larger topologies. Hash/list/range/schema routing is
valid at count one; explicit destinations must satisfy `0 <= shard < pg.shards`.
Growing the count adds shard instances without changing the configuration shape
or the existing shard-zero identity. There is no separate enable-sharding flag.

**Shape compatibility is not automatic data migration.** Changing the count on
a populated deployment requires coordinated data redistribution and cutover.
Do not simply apply a new shard count to live data; this POC does not automate
or guard that operational migration.

### Native placement and replication

CNPG owns these policies. The example above requires distinct zones through
native required anti-affinity, and waits for one quorum standby. Choosing
preferred affinity instead can allow more instances than zones. Durability
(`required`/`preferred`), quorum/priority method, synchronous count, and failover
quorum are independently configurable under `template.spec.postgresql`.
No legacy `syncReplicaElectionConstraint` is injected by the renderer.

For a single AZ, select eligible nodes through native affinity/node selectors;
use host anti-affinity if desired. A single PostgreSQL instance is also supported:
replica backends/read services are omitted, but explicit native replication
settings are not silently rewritten. Scheduling feasibility and operational
policy remain the user's responsibility.

### Small local profile and kind configuration

The checked-in POC keeps **four shards, three PostgreSQL instances per shard,
and three PgDog pods**, but uses intentionally small local settings:

| Per pod | CPU request / limit | Memory request / limit | PVC |
| --- | --- | --- | --- |
| PostgreSQL | 50m / 250m | 128Mi / 256Mi | 512Mi |
| PgDog | 25m / 100m | 32Mi / 128Mi | — |

PostgreSQL uses 32MB shared buffers, 64 connections, 1MB work memory, 16MB
maintenance work memory, 8MB autovacuum work memory, 32MB minimum / 64MB maximum
WAL targets, and disables JIT. WAL targets are not hard disk limits; replication
slots can retain additional WAL. These settings are for the small seed/routing
fixture, not production workloads.

For the database and proxy pods combined, that is **675m CPU and 1632Mi memory
requested**, with 3.3 CPU / 3456Mi memory limits and 6Gi of requested PVC storage.
This excludes kind nodes, Kubernetes/CNPG components, and other cluster overhead.
PVC requests also do not impose a filesystem quota on kind's local-path storage.

**Existing 1Gi PVCs cannot be shrunk in place.** The 512Mi setting is for a fresh
deployment. Do not apply the reduced storage request to an existing cluster or
delete/recreate the cluster unless its data is disposable or backed up.

Local test-environment fixtures live under `tests/local/`, separate from the
reusable CUE libraries. kind is configured in plain `tests/local/kind.yaml`, not
in CUE. Edit that file directly for native networking, nodes, labels, mounts,
ports, or kubeadm patches.
The local fixture has one control-plane and three worker nodes in zones a/b/c.
It is not derived from database or proxy counts: adjust the node configuration
yourself when changing capacity or placement requirements.

`just up` reads `tests/local/kind.yaml`; cluster selection/deletion derive the
name from that same file. `just seed` reads the hand-written schema and seed data
from `tests/local/sql/`. These are disposable test fixtures, not production
migrations: the schema script drops and recreates its test tables.
CUE renders application resources and generated schema assertions under
`rendered/`. Recreate kind only when its creation-time settings need to change.

### Native schemas and validation

`lib/topology/upstream/*_gen.cue` is generated from the Kubernetes OpenAPI schema
matching `KIND_NODE_IMAGE` and the CNPG CRD in `CNPG_MANIFEST`. Regenerate with
`just update-schemas` inside the devShell after changing those pins. Ordinary
rendering and tests use the checked-in definitions and need no network.

The conversion preserves native types, treats structured objects as closed,
and handles Kubernetes `int-or-string`. Kubernetes CEL/admission checks and
quantity semantics still require `kubectl apply --dry-run=server`; CUE validation
is not a substitute for the API server.

`just check-topology` tests defaults, routed singleton, one-to-four-shard shape
compatibility, single-instance PostgreSQL, native template passthrough, and
invalid inputs. Live checks follow the declared native CNPG anti-affinity and
required synchronous policy, accepting both `sync` and `quorum` replica states.
`just check-render` compares a fresh render with the working-tree golden files
without overwriting them, so reviewed uncommitted snapshot updates work too.
The live seed/routing test still uses the POC's `dog` database and 400-row fixture.

## Deviations discovered while implementing

Recorded here because they corrected assumptions in the plan and are the kind
of thing that would otherwise surprise a future reader:

- **CNPG sync method `any` vs `first`.** `synchronous.method: any` yields
  `sync_state = quorum` with no single elected sync replica; `method: first`
  yields exactly one `sync` replica. The POC template explicitly selects `any`;
  the renderer passes either policy through. See
  `docs/reference/cnpg-placement.md`.
- **PgDog config key names.** `[[sharded_tables]]` uses `name` (the table
  name), not `table`; `data_type` is `bigint|uuid|varchar|vector` (not `text`).
  The PgDog image has no ENTRYPOINT and requires the `run` subcommand. See
  `docs/reference/pgdog-config.md`.
- **`trafficDistribution` renamed.** Kubernetes 1.36 deprecates `PreferClose`
  in favour of `PreferSameZone`; the read Services use `PreferSameZone`.
- **Seed shape.** `INSERT ... SELECT` is not sharded by PgDog (all rows landed
  on one shard); single-tuple `INSERT ... VALUES` is. The seed emits one
  statement per row.
- **CUE package layout.** The root imports the libraries, never vice versa.
  `topology.cue` holds user configuration and `outputs.cue` composes the pure
  derivation and render definitions. `just render` exports from the root.

## CUE layout

```text
topology.cue                user configuration: topology.pg / topology.dog
outputs.cue                 root composition and public exports
lib/
  topology.cue             validated configuration → shard names and endpoints
  topology/
    cluster.cue            cluster, shard, topology, and routing definitions
    kubernetes.cue         aliases to native upstream resource types
    upstream/              generated Kubernetes/CNPG definitions
  render/
    cnpg.cue               CNPG clusters and read services
    pgdog.cue              PgDog configuration and deployment
    namespace.cue          namespace and credentials
    sql.cue                generated schema assertions
    manifests.cue          assembled output streams
tests/
  topology.cue             offline topology fixtures
  local/
    kind.yaml              independent local Kubernetes fixture (plain YAML)
    sql/
      schema.sql           disposable routing-test tables
      seed.sql             400-row routing-test dataset
```
