package cnpgdog

import "github.com/hsyed/cnpg-dog/lib/schema"

// User configuration. Omit pg.shards for a singleton of the same shard topology.
// This POC explicitly uses four shards to exercise the routing checks.
topology: schema.#Topology & {
	name: "dog"
	pg: {
		shards: 4
		// Native CNPG Cluster template; no implicit availability preset.
		template: {
			metadata: labels: "app.kubernetes.io/part-of": "cnpg-dog"
			spec: {
				instances: 3 // Includes the primary.
				imageName: "ghcr.io/cloudnative-pg/postgresql:18"
				// Small local POC, not production sizing. PVCs cannot shrink
				// in-place: this size is for a fresh kind deployment.
				storage: size: "512Mi"
				resources: {
					requests: {cpu: "50m", memory: "128Mi"}
					limits: {cpu: "250m", memory: "256Mi"}
				}
				affinity: {
					topologyKey:         "topology.kubernetes.io/zone"
					podAntiAffinityType: "required"
				}
				postgresql: {
					parameters: {
						shared_buffers:       "32MB"
						max_connections:      "64"
						work_mem:             "1MB"
						maintenance_work_mem: "16MB"
						autovacuum_work_mem:  "8MB"
						min_wal_size:         "32MB"
						max_wal_size:         "64MB"
						jit:                  "off"
					}
					synchronous: {
						method:         "any"
						number:         1
						dataDurability: "required"
					}
				}
			}
		}
	}
	dog: {
		replicas: 3
		resources: {
			requests: {cpu: "25m", memory: "32Mi"}
			limits: {cpu: "100m", memory: "128Mi"}
		}
		topologySpreadConstraints: [{
			maxSkew:           1
			topologyKey:       "topology.kubernetes.io/zone"
			whenUnsatisfiable: "DoNotSchedule"
			labelSelector: matchLabels: app: "pgdog"
		}]
		shardedColumns: [
			{column: "tenant_id", dataType: "bigint"},
			{name: "users", column: "company_id", dataType: "uuid"},
			{column: "region", dataType: "varchar", mapping: [
				{values: ["us", "ca"], shard: 0},
				{values: ["eu"], shard: 1},
				{shard: 2},
			]},
			{column: "order_id", dataType: "bigint", mapping: [
				{start: 1, end: 100, shard: 0},
				{start: 100, end: 200, shard: 1},
				{shard: 2},
			]},
		]
		shardedSchemas: [
			{name: "customer_a", shard: 0},
			{name: "customer_b", shard: 1},
		]
	}
}

// Native kind configuration. Omit nodes for the generated three-zone fixture,
// or provide the complete native node list (labels, mounts, ports, patches).
kind: {
	name: "cnpg-dog"
	networking: {
		apiServerAddress: "127.0.0.1"
		ipFamily:         "ipv4"
	}
}
