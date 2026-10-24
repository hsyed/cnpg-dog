package render

import (
	"encoding/toml"
	topologyTypes "github.com/hsyed/cnpg-dog/lib/topology"
)

#Output: {
	topology:   _
	pgdogImage: _

	// Native PgDog key names: see docs/reference/pgdog-config.md.
	_pgdogConfig: {
		general: {
			host:              "0.0.0.0"
			port:              6432
			workers:           2
			default_pool_size: 10
		}
		databases: [for s in topology.shards for e in [
			{name: s.db, host: s.rw, port: 5432, role: "primary", database_name: s.db},
			if topology.pg.template.spec.instances > 1 {
				{name: s.db, host: s.ro, port: 5432, role: "replica", database_name: s.db}
			},
		] {
			e
			shard: s.id
		}]
		sharded_tables: [for c in topology.dog.shardedColumns {
			database:  topology.name
			column:    c.column
			data_type: c.dataType
			if c.name != _|_ {name: c.name}
			if c.mapping != _|_ {
				mapping: [for m in c.mapping {
					shard: m.shard
					if m.values != _|_ {values: m.values}
					if m.start != _|_ {start: m.start}
					if m.end != _|_ {end: m.end}
				}]
			}
		}]
		sharded_schemas: [for s in topology.dog.shardedSchemas {
			database: topology.name
			shard:    s.shard
			if s.name != _|_ {name: s.name}
		}]
	}
	_pgdogUsers: users: [{
		name:     topology.name
		database: topology.name
		password: "dogpassword"
	}]
	_pgdogConfigMap: topologyTypes.#ConfigMap & {
		apiVersion: "v1"
		kind:       "ConfigMap"
		metadata: {
			name:      "pgdog"
			namespace: topology.name
			annotations: "argocd.argoproj.io/sync-wave": "2"
		}
		data: "pgdog.toml": toml.Marshal(_pgdogConfig)
	}
	_pgdogSecret: topologyTypes.#Secret & {
		apiVersion: "v1"
		kind:       "Secret"
		metadata: {
			name:      "pgdog-users"
			namespace: topology.name
			annotations: "argocd.argoproj.io/sync-wave": "0"
		}
		stringData: "users.toml": toml.Marshal(_pgdogUsers)
	}
	_pgdogDeployment: topologyTypes.#Deployment & {
		apiVersion: "apps/v1"
		kind:       "Deployment"
		metadata: {
			name:      "pgdog"
			namespace: topology.name
			annotations: "argocd.argoproj.io/sync-wave": "2"
		}
		spec: {
			replicas: topology.dog.replicas
			selector: matchLabels: app: "pgdog"
			template: {
				metadata: labels: app: "pgdog"
				spec: {
					if topology.dog.affinity != _|_ {
						affinity: topology.dog.affinity
					}
					if topology.dog.topologySpreadConstraints != _|_ {
						topologySpreadConstraints: topology.dog.topologySpreadConstraints
					}
					containers: [{
						name:  "pgdog"
						image: pgdogImage
						command: ["/usr/local/bin/pgdog"]
						args: ["--config", "/etc/pgdog/pgdog.toml", "--users", "/etc/pgdog/users.toml", "run"]
						if topology.dog.resources != _|_ {
							resources: topology.dog.resources
						}
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
	_pgdogService: topologyTypes.#Service & {
		apiVersion: "v1"
		kind:       "Service"
		metadata: {
			name:      "pgdog"
			namespace: topology.name
			annotations: "argocd.argoproj.io/sync-wave": "2"
		}
		spec: {
			type: "ClusterIP"
			selector: app: "pgdog"
			ports: [{name: "pgdog", port: 6432, targetPort: 6432}]
		}
	}
}
