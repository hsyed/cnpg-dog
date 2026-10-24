package tests

import (
	"github.com/hsyed/cnpg-dog/lib"
	"github.com/hsyed/cnpg-dog/lib/render"
	"github.com/hsyed/cnpg-dog/lib/topology"
)

#Case: {
	config: topology.#Topology & {
		name: "dog"
		pg: template: spec: storage: size: "1Gi"
	}
	let input = config
	derived: (lib.#Topology & {config: input}).out
	output: render.#Output & {
		topology:   derived
		pgdogImage: "pgdog:test"
	}
}

// Define routing at shard count one. Scaling changes only the count.
_growthRules: {
	shardedColumns: [
		{column: "tenant_id", dataType: "bigint"},
		{name: "jobs", column: "region", dataType: "varchar", mapping: [
			{values: ["us"], shard: 0},
			{shard: 0},
		]},
	]
	shardedSchemas: [{name: "customer_a", shard: 0}]
}

cases: {
	defaults: #Case
	singleton: #Case & {config: dog: _growthRules}
	expanded: #Case & {
		config: {
			pg: shards: 4
			dog: _growthRules
		}
	}
	singleInstance: #Case & {
		config: {
			pg: template: spec: instances: 1
			dog: replicas: 1
		}
	}
	nativeFields: #Case & {
		config: {
			pg: {
				shards: 4
				template: {
					metadata: {
						labels: team:                      "platform"
						annotations: "example.com/policy": "native"
					}
					spec: {
						instances: 5
						imageName: "ghcr.io/cloudnative-pg/postgresql:18"
						storage: {
							storageClass: "fast-rwo"
							pvcTemplate: {
								accessModes: ["ReadWriteOnce"]
								volumeMode: "Filesystem"
							}
						}
						resources: {
							requests: {cpu: "500m", memory: "1Gi"}
							limits: memory: "2Gi"
						}
						affinity: {
							topologyKey:         "topology.kubernetes.io/zone"
							podAntiAffinityType: "preferred"
							nodeSelector: workload: "postgres"
							tolerations: [{
								key:      "workload"
								operator: "Equal"
								value:    "postgres"
								effect:   "NoSchedule"
							}]
						}
						postgresql: {
							parameters: max_connections: "200"
							synchronous: {
								method:         "any"
								number:         2
								dataDurability: "preferred"
								failoverQuorum: false
							}
						}
						primaryUpdateStrategy: "supervised"
						bootstrap: initdb: {
							database: "dog"
							owner:    "dog"
							secret: name: "dog-app"
							postInitSQL: ["SELECT 1"]
						}
					}
				}
			}
			dog: {
				replicas: 2
				resources: {
					requests: {cpu: "250m", memory: "128Mi"}
					limits: memory: "512Mi"
				}
				affinity: nodeAffinity: preferredDuringSchedulingIgnoredDuringExecution: [{
					weight: 1
					preference: matchExpressions: [{
						key:      "workload"
						operator: "In"
						values: ["proxy"]
					}]
				}]
				topologySpreadConstraints: [{
					maxSkew:           1
					topologyKey:       "topology.kubernetes.io/zone"
					whenUnsatisfiable: "ScheduleAnyway"
					labelSelector: matchLabels: app: "pgdog"
				}]
				shardedColumns: [
					{column: "tenant_id", dataType: "bigint"},
					{name: "jobs", column: "region", dataType: "varchar", mapping: [
						{values: ["us"], shard: 0},
						{shard: 3},
					]},
				]
				shardedSchemas: [{name: "customer_a", shard: 2}]
			}
		}
	}
}

// Raw data is checked against #Case only by the negative-test runner.
invalid: {
	shardCount: {config: {pg: shards: 0}}
	instanceCount: {config: {pg: template: spec: instances: 0}}
	proxyCount: {config: {dog: replicas: 0}}
	oldReplicas: {config: {pg: replicas: 3}}
	oldAvailability: {config: {pg: availability: "multi-az"}}
	oldInstances: {config: {pg: instances: 3}}
	columnMapping: {config: {
		pg: shards: 2
		dog: shardedColumns: [{
			column: "region", dataType: "varchar", mapping: [{shard: 2}]
		}]
	}}
	schemaMapping: {config: {
		pg: shards: 2
		dog: shardedSchemas: [{name: "customer_a", shard: -1}]
	}}
	singletonMapping: {config: {
		dog: shardedSchemas: [{name: "customer_a", shard: 1}]
	}}
	storageType: {config: {pg: template: spec: storage: storageClass: 123}}
	storageField: {config: {pg: template: spec: storage: storageClas: "typo"}}
	resourceType: {config: {pg: template: spec: resources: requests: cpu: {bad: "quantity"}}}
	affinityType: {config: {pg: template: spec: affinity: nodeSelector: "not-a-map"}}
	replicationType: {config: {pg: template: spec: postgresql: synchronous: {
		method: "invalid"
		number: 1
	}}}
	templateIdentity: {config: {pg: template: metadata: name: "wrong"}}
}
