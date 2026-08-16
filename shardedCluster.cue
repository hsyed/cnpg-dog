package cnpgdog

// The values. Everything else — the schemas that interpret them, the fabric
// derivation, and the renderers — lives in lib/.

shardedCluster: {
	name:      "dog"
	shards:    4
	pgVersion: "18"
	storage:   "1Gi"
	shardedColumns: [
		// Hash, every table with this column.
		{column: "tenant_id", dataType: "bigint"},
		// Hash, one table only.
		{name: "users", column: "company_id", dataType: "uuid"},
		// List: explicit value -> shard, with a fallback.
		{column: "region", dataType: "varchar", mapping: [
			{values: ["us", "ca"], shard: 0},
			{values: ["eu"], shard: 1},
			{shard: 2},
		]},
		// Range: bounded ranges, with a fallback.
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
