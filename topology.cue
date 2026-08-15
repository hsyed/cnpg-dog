package cnpgdog

import "github.com/hsyed/cnpg-dog/schema"

topology: schema.#Topology & {
	name:   "dog"
	shards: 4
	zones: ["a", "b", "c"]
	pgVersion: "18"
	storage:   "1Gi"
}

shardedTables: [schema.#ShardedTable & {
	table:    "events"
	column:   "tenant_id"
	dataType: "bigint"
}]
