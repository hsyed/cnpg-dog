package lib

import (
	"list"
	"github.com/hsyed/cnpg-dog:cnpgdog"
)

// #Topology is the complete set of knobs for the fabric.
#Topology: {
	name:      string
	shards:    int & >=1
	pgVersion: string
	storage:   string
}

// #ShardedTable is the one fact PgDog needs about the schema. Consumed twice:
// by pgdog.toml and by the generated schema assertion.
#ShardedTable: {
	table:    string
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
	topology: #Topology
	zones: [...string] & [_, ...]
	shards: [...#Shard]
	shardedTables: [...#ShardedTable]
}

// The raw values from the root, validated against their schemas.
_topology: cnpgdog.topology & #Topology
_zones: cnpgdog.zones & [...string] & [_, ...]
_shardedTables: cnpgdog.shardedTables & [...#ShardedTable]

fabric: #Fabric & {
	topology:      _topology
	zones:         _zones
	shardedTables: _shardedTables
	shards: [for i in list.Range(0, _topology.shards, 1) {
		id:      i
		cluster: "\(_topology.name)-s\(i)"
		rw:      "\(cluster)-rw"
		ro:      "\(cluster)-read"
		db:      _topology.name
	}]
}
