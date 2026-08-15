# CNPG + PgDog Sharding POC

A cloud-native Postgres fabric where [CloudNativePG](https://cloudnative-pg.io/)
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

`just check` runs five gates: render determinism (`check-render`), manifest
shape (`check-manifests`), the rendered PgDog routing table
(`check-pgdog-config`), per-zone placement (`scripts/check-placement.sh`), and
partition/completeness/reachability (`scripts/check-routing.sh`).

## Deviations discovered while implementing

Recorded here because they corrected assumptions in the plan and are the kind
of thing that would otherwise surprise a future reader:

- **CNPG sync method `any` vs `first`.** `synchronous.method: any` yields
  `sync_state = quorum` with no single elected sync replica; `method: first`
  yields exactly one `sync` replica. The renderer uses `first`. See
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
- **CUE package layout.** `topology.cue` at the root is pure values (no
  schemas, no imports); everything else lives under `lib/` as one
  `package lib` — the schemas (`#Topology`, `#ShardedTable`, `#Shard`,
  `#Fabric`), the `fabric` derivation, the partial k8s/CNPG schemas, and the
  renderers.
