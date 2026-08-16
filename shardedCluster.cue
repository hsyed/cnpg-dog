package cnpgdog

// The values. Everything else — the schemas that interpret them, the fabric
// derivation, and the renderers — lives in lib/.

shardedCluster: {
	name:      "dog"
	shards:    4
	pgVersion: "18"
	storage:   "1Gi"
	zones: ["a", "b", "c"]
	shardedColumns: [{
		column:   "tenant_id"
		dataType: "bigint"
	}]
}
