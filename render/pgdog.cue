package render

import (
	"encoding/toml"
	"github.com/hsyed/cnpg-dog/lib"
)

// Key names are verified against the pinned image — see docs/reference/pgdog-config.md.
// Notably: sharded_tables uses `name` (the table name), NOT `table`; the data_type
// enum is bigint|uuid|varchar|vector; and the binary requires the `run` subcommand.

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
	sharded_tables: [for t in lib.fabric.tables {
		database:  lib.fabric.shardedCluster.name
		name:      t.table
		column:    t.column
		data_type: t.dataType
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
