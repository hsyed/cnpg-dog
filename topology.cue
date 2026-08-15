package cnpgdog

// The values. Everything else — the schemas that interpret them, the fabric
// derivation, and the renderers — lives in lib/.

topology: {
	name:   "dog"
	shards: 4
	zones: ["a", "b", "c"]
	pgVersion: "18"
	storage:   "1Gi"
}

shardedTables: [{
	table:    "events"
	column:   "tenant_id"
	dataType: "bigint"
}]
