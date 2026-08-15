package schema

// #Topology is the complete set of knobs for the fabric.
#Topology: {
	name:                         string
	shards:                       int & >=1
	zones: [...string] & [_, ...] // at least one zone
	pgVersion:                    string
	storage:                      string
}

// #Shard is a single derived shard. Every name in the system comes from here;
// nothing else may build a service name by concatenation.
#Shard: {
	id:      int & >=0
	cluster: string // CNPG Cluster metadata.name
	rw:      string // CNPG-owned primary service
	ro:      string // our read service, PreferSameZone
	db:      string // database name
}

// #ShardedTable is the one fact PgDog needs about the schema. It is consumed
// twice: by pgdog.toml and by the generated schema assertion.
#ShardedTable: {
	table:    string
	column:   string
	dataType: "bigint" | "uuid" | "varchar" | "vector"
}

#Fabric: {
	topology: #Topology
	zones: [...string]
	shards: [...#Shard]
	shardedTables: [...#ShardedTable]
}
