# CNPG placement — verified findings

Verified empirically against CNPG 1.30.0 on kind (Kubernetes v1.36.1),
PostgreSQL 18.4, on 2026-08-15. This file is the source of truth for the
field spellings the CUE renderer uses. `render/cnpg.cue` must not be written
from memory.

## Verified field spellings

The following `spec` block was server-side dry-run accepted and applied, and
the cluster reached `Ready`:

```yaml
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:18.4
  storage:
    size: 256Mi
  postgresql:
    synchronous:
      method: first
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

## Synchronous replication: `any` vs `first` (important)

The plan originally assumed `synchronous.method: any, number: 1` yields a
single observable sync replica. It does not.

- `method: any` (quorum) sets `synchronous_standby_names = ANY 1 (...)`. Every
  eligible replica reports `sync_state = quorum`, never `sync`. There is no
  single elected sync replica to point at.
- `method: first` (priority) sets `synchronous_standby_names = FIRST 1 (...)`.
  Exactly one replica reports `sync_state = sync`; the rest report `potential`.

Observed with `method: first, number: 1`:

```
FIRST 1 ("probe-s0-2","probe-s0-3","probe-s0-1")
probe-s0-2 | sync      | priority 1
probe-s0-3 | potential | priority 2
```

The placement check needs a single `sync` replica, so the renderer MUST use
`method: first`, not `any`.

## syncReplicaElectionConstraint is legacy-only

CNPG docs state `.spec.postgresql.syncReplicaElectionConstraint` "only applies
to the legacy implementation of synchronous replication"
(`minSyncReplicas`/`maxSyncReplicas`, which maps to quorum/`ANY`). It is kept
in the renderer because it documents the cross-zone intent and does not harm;
with `instances == len(zones)` and `topologySpreadConstraints` (below) the
cross-zone property is guaranteed regardless.

## Cross-zone is guaranteed by spread, not by the constraint

With `instances: 3`, three zone-labeled workers, and
`topologySpreadConstraints` (`maxSkew: 1`, `DoNotSchedule`), every pod lands in
a distinct zone. Primary and sync replica therefore always sit in different
zones. `syncReplicaElectionConstraint` is the general-case guard; in this
POC's 3-instance/3-zone setup it is redundant but harmless.

## Verified cluster facts

- Readiness condition name: `Ready` (valid for `kubectl wait --for=condition=Ready`).
- Replica pod label: `cnpg.io/instanceRole=replica` (primary is `=primary`).
- Pod zone label (node label copied onto pod): `topology.kubernetes.io/zone`.
- `status.currentPrimary` holds the primary pod name.
- Sync replica state query:
  `select application_name from pg_stat_replication where sync_state='sync'`.

## Observed placement

```
probe-s0-1  primary   zone c
probe-s0-2  sync      zone a
probe-s0-3  potential zone b
```

One pod per zone; sync replica (zone a) is outside the primary's zone (zone c).
