package lib

// #ShardedCluster is the complete set of knobs for the fabric.
#ShardedCluster: {
	name:      string
	shards:    int & >=1
	pgVersion: string
	storage:   string
	shardedColumns: [...#ShardedColumn]
	shardedSchemas: [...#ShardedSchema]
}

// #ShardedColumn is column-based sharding. The function is inferred from the
// mapping, exactly like PgDog: no mapping = hash; `values` = list; `start`/`end`
// = range; `shard` only = default fallback. `name` omitted = every table with
// this column; `name` set = only that table.
#ShardedColumn: {
	name?:    string
	column:   string
	dataType: "bigint" | "uuid" | "varchar"
	mapping?: [...#ShardMapping]
}

// #ShardMapping is one value->shard rule.
#ShardMapping: {
	shard:                          int & >=0
	values?: [...int] | [...string] // list rule
	start?:                         int | string // range rule (inclusive)
	end?:                           int | string // range rule (exclusive)
}

// #ShardedSchema is schema-based sharding. `name` omitted = default routing.
#ShardedSchema: {
	name?: string
	shard: int & >=0
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

#Fabric: {
	shardedCluster: #ShardedCluster
	shards: [...#Shard]
	shardedColumns: [...#ShardedColumn]
	shardedSchemas: [...#ShardedSchema]
}
