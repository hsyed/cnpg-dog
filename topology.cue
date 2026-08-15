package cnpgdog

// The values. Everything else — the schemas that interpret them, the fabric
// derivation, and the renderers — lives in lib/.

topology: {
	name:      "dog"
	shards:    4
	pgVersion: "18"
	storage:   "1Gi"
}

// Placement, not data topology: the availability zones the fabric spreads
// across. Consumed by kind, the CNPG spread constraints, and PgDog replicas.
zones: ["a", "b", "c"]

shardedTables: [{
	table:    "events"
	column:   "tenant_id"
	dataType: "bigint"
}]
