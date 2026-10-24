# PgDog config — verified format

Verified empirically against `ghcr.io/pgdogdev/pgdog:v0.1.53` on 2026-08-15.
This file is the source of truth for the TOML key names the CUE renderer emits.
`lib/render/pgdog.cue` must not be written from memory or from the plan.

## CLI invocation (critical)

PgDog v0.1.53 uses subcommands. The image has **no ENTRYPOINT** — its Cmd is
`["/usr/local/bin/pgdog"]` — so a Kubernetes Deployment must set both `command`
and `args` explicitly:

```yaml
command: ["/usr/local/bin/pgdog"]
args:    ["--config", "/etc/pgdog/pgdog.toml", "--users", "/etc/pgdog/users.toml", "run"]
```

Setting `args` alone replaces the binary path and the container fails with
`exec: "--config": executable file not found`. The `run` subcommand is also
required — without it the binary prints help and exits, so a "running" pod
crashes in a loop.

The `-c/--config` and `-u/--users` flags precede the subcommand. There is a
`configcheck` subcommand that validates both files and exits non-zero on any
error; it is the cheapest parse-only gate.

## Key names (all verified)

`[[databases]]` (one entry per shard per role):

- `name` — client-facing database name (same value for all entries of one cluster)
- `host` — backend DNS name or IP
- `port` — backend port (default 5432)
- `role` — `primary` | `replica` | `auto` (default `primary`)
- `database_name` — database on the backend (defaults to `name`)
- `shard` — shard number, starts at 0 (default 0)

`[[sharded_tables]]`:

- `database` — the `[[databases]]` name the table lives in
- `name` — **the table name** (NOT `table`; the plan's `table` key is wrong)
- `column` — the sharded column name
- `data_type` — `bigint` | `uuid` | `varchar` | `vector`
  (`text` is NOT a valid value; text columns are sharded as `varchar`)

`[general]`:

- `host` (default `0.0.0.0`), `port` (default 6432), `workers` (default 2),
  `default_pool_size` (default 10)

`[[users]]` (in `users.toml`):

- `name`, `database`, `password`

## Validation behaviour

Both unknown keys and invalid enum values are rejected at load time with a
precise error naming the offending line:

```
ERROR failed to load /etc/pgdog/pgdog.toml: unknown field `bogus_key`, line 23
ERROR failed to load /etc/pgdog/pgdog.toml: unknown variant `leader`, expected one of `primary`, `replica`, `auto`, line 11
```

So a config typo cannot pass silently; `configcheck` is a reliable gate. The
admin password is auto-generated at startup (a WARN, not an error) — no admin
section is required.

## Working config (verbatim)

`pgdog.toml`:

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
name = "events"
column = "tenant_id"
data_type = "bigint"
```

`users.toml`:

```toml
[[users]]
name = "dog"
database = "dog"
password = "dogpassword"
```
