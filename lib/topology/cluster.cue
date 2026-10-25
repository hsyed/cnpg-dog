package topology

import "github.com/hsyed/cnpg-dog/lib/topology/upstream"

// Only deployment policy and routing rules are ours. Storage, resources, and
// affinity use the native CNPG/Kubernetes types without parallel wrappers.
#Topology: {
	name: string
	pg: {
		shards: *1 | int & >=1
		template: upstream.#Cluster & {
			apiVersion: "postgresql.cnpg.io/v1"
			kind:       "Cluster"
			metadata: {}
			// Add only a default; the native schema owns the type and bounds.
			spec: instances: *3 | _
		}
	}
	dog: {
		replicas:   *3 | int & >=1
		resources?: upstream.#ResourceRequirements
		affinity?:  upstream.#Affinity
		topologySpreadConstraints?: [...upstream.#TopologySpreadConstraint]
		shardedColumns: *[] | [...#ShardedColumn]
		shardedSchemas: *[] | [...#ShardedSchema]
	}

	// A singleton uses the same routing model; only valid destination IDs vary.
	let shardCount = pg.shards
	dog: {
		shardedColumns: [...{
			#ShardedColumn
			mapping?: [...{#ShardMapping, shard: <shardCount}]
		}]
		shardedSchemas: [...{#ShardedSchema, shard: <shardCount}]
	}
}

// No mapping = hash; values = list; start/end = range; shard alone = fallback.
#ShardedColumn: {
	name?:    string
	column:   string
	dataType: "bigint" | "uuid" | "varchar"
	// Mapping values must match the column's data type.
	let T = {bigint: int, uuid: string, varchar: string}[dataType]
	mapping?: [...{#ShardMapping, #T: T}]
}

// One shape per entry: a list (values) cannot also be a range (start/end).
#ShardMapping: {
	#T:    _
	shard: int & >=0
	values?: [#T, ...#T]
	start?: #T
	end?:   #T
	if values != _|_ {
		start?: _|_
		end?:   _|_
	}
}

#ShardedSchema: {
	name?: string
	shard: int & >=0
}

// All names and endpoints are derived once, never reconstructed by renderers.
#Shard: {
	id:      int & >=0
	cluster: string
	rw:      string
	ro:      string
	db:      string
}

#DerivedTopology: {
	#Topology
	shards: [...#Shard]
}
