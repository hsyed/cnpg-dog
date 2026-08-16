package render

import (
	"encoding/toml"
	"github.com/hsyed/cnpg-dog/lib"
)

// Key names are verified against the pinned image — see docs/reference/pgdog-config.md.
// Notably: omitting `name` in sharded_tables shards every table with the column;
// the data_type enum is bigint|uuid|varchar|vector; the binary needs `run`.

// Injected by the render recipe: `-t pgdogImage="${PGDOG_IMAGE}"`.
_pgdogImage: string @tag(pgdogImage)

_pgdogConfig: {
	general: {
		host:              "0.0.0.0"
		port:              6432
		workers:           2
		default_pool_size: 10
	}
	databases: [for s in lib.fabric.shards for e in [
		{name: s.db, host: s.rw, port: 5432, role: "primary", shard: s.id, database_name: s.db},
		{name: s.db, host: s.ro, port: 5432, role: "replica", shard: s.id, database_name: s.db},
	] {e}]
	sharded_tables: [for c in lib.fabric.shardedColumns {
		database:  lib.fabric.shardedCluster.name
		column:    c.column
		data_type: c.dataType
		if c.name != _|_ {
			name: c.name
		}
		if c.mapping != _|_ {
			mapping: [for m in c.mapping {
				shard: m.shard
				if m.values != _|_ {
					values: m.values
				}
				if m.start != _|_ {
					start: m.start
				}
				if m.end != _|_ {
					end: m.end
				}
			}]
		}
	}]
	sharded_schemas: [for s in lib.fabric.shardedSchemas {
		database: lib.fabric.shardedCluster.name
		shard:    s.shard
		if s.name != _|_ {
			name: s.name
		}
	}]
}

_pgdogUsers: users: [{
	name:     lib.fabric.shardedCluster.name
	database: lib.fabric.shardedCluster.name
	password: "dogpassword"
}]

_pgdogConfigMap: lib.#ConfigMap & {
	apiVersion: "v1"
	kind:       "ConfigMap"
	metadata: {
		name:      "pgdog"
		namespace: lib.fabric.shardedCluster.name
		annotations: "argocd.argoproj.io/sync-wave": "2"
	}
	data: "pgdog.toml": toml.Marshal(_pgdogConfig)
}

_pgdogSecret: lib.#Secret & {
	apiVersion: "v1"
	kind:       "Secret"
	metadata: {
		name:      "pgdog-users"
		namespace: lib.fabric.shardedCluster.name
		annotations: "argocd.argoproj.io/sync-wave": "0"
	}
	stringData: "users.toml": toml.Marshal(_pgdogUsers)
}

_pgdogDeployment: lib.#Deployment & {
	apiVersion: "apps/v1"
	kind:       "Deployment"
	metadata: {
		name:      "pgdog"
		namespace: lib.fabric.shardedCluster.name
		annotations: "argocd.argoproj.io/sync-wave": "2"
	}
	spec: {
		replicas: len(zones)
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
					image: _pgdogImage
					command: ["/usr/local/bin/pgdog"]
					args: ["--config", "/etc/pgdog/pgdog.toml", "--users", "/etc/pgdog/users.toml", "run"]
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

_pgdogService: lib.#Service & {
	apiVersion: "v1"
	kind:       "Service"
	metadata: {
		name:      "pgdog"
		namespace: lib.fabric.shardedCluster.name
		annotations: "argocd.argoproj.io/sync-wave": "2"
	}
	spec: {
		type: "ClusterIP"
		selector: app: "pgdog"
		ports: [{name: "pgdog", port: 6432, targetPort: 6432}]
	}
}
