package lib

import (
	"list"
	"github.com/hsyed/cnpg-dog:cnpgdog"
)

// #ShardedCluster is the complete set of knobs for the fabric.
#ShardedCluster: {
	name:      string
	shards:    int & >=1
	pgVersion: string
	storage:   string
	shardedColumns: [...#ShardedColumn]
}

// #ShardedColumn is the one fact PgDog needs about the schema: every table
// with this column (of this type) is sharded on it. Consumed twice: by
// pgdog.toml and by the generated schema assertion.
#ShardedColumn: {
	column:   string
	dataType: "bigint" | "uuid" | "varchar" | "vector"
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
}

// The raw values from the root, validated against their schemas.
_shardedCluster: cnpgdog.shardedCluster & #ShardedCluster

fabric: #Fabric & {
	shardedCluster: _shardedCluster
	shardedColumns: _shardedCluster.shardedColumns
	shards: [for i in list.Range(0, _shardedCluster.shards, 1) {
		id:      i
		cluster: "\(_shardedCluster.name)-s\(i)"
		rw:      "\(cluster)-rw"
		ro:      "\(cluster)-read"
		db:      _shardedCluster.name
	}]
}
