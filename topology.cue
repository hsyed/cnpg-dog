package cnpgdog

// #Topology is the complete set of knobs for the fabric.
#Topology: {
	name:                         string
	shards:                       int & >=1
	zones: [...string] & [_, ...] // at least one zone
	pgVersion:                    string
	storage:                      string
}

topology: #Topology & {
	name:   "dog"
	shards: 4
	zones: ["a", "b", "c"]
	pgVersion: "18"
	storage:   "1Gi"
}

// #ShardedTable is the one fact PgDog needs about the schema. Consumed twice:
// by pgdog.toml and by the generated schema assertion.
#ShardedTable: {
	table:    string
	column:   string
	dataType: "bigint" | "uuid" | "varchar" | "vector"
}

shardedTables: [#ShardedTable & {
	table:    "events"
	column:   "tenant_id"
	dataType: "bigint"
}]
