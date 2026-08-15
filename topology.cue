package cnpgdog

topology: #Topology & {
	name:   "dog"
	shards: 4
	zones: ["a", "b", "c"]
	pgVersion: "18"
	storage:   "1Gi"
}

shardedTables: [#ShardedTable & {
	table:    "events"
	column:   "tenant_id"
	dataType: "bigint"
}]
