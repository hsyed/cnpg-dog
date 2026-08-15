# CNPG + PgDog Sharding POC

A cloud-native Postgres fabric where [CloudNativePG](https://cloudnative-pg.io/)
manages the shards and [PgDog](https://pgdog.dev/) provides sharded routing in
front of them, with the entire topology encoded in CUE. See
`docs/superpowers/specs/2026-08-15-cnpg-pgdog-poc-design.md` for the design and
`docs/superpowers/plans/2026-08-15-cnpg-pgdog-poc.md` for the implementation plan.

## Running

```bash
nix develop
just up && just apply && just seed && just check
```

Every version pin (kind node image, CNPG operator release, PgDog image,
Postgres image) lives in `flake.nix` and nowhere else. The devShell exports
them as environment variables that the Justfile recipes read.
