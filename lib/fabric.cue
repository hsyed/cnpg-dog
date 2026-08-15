package lib

import (
	"list"
	"github.com/hsyed/cnpg-dog:cnpgdog"
)

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
	topology: cnpgdog.#Topology
	zones: [...string]
	shards: [...#Shard]
	shardedTables: [...cnpgdog.#ShardedTable]
}

fabric: #Fabric & {
	topology:      _t
	zones:         _t.zones
	shardedTables: _st
	shards: [for i in list.Range(0, _t.shards, 1) {
		id:      i
		cluster: "\(_t.name)-s\(i)"
		rw:      "\(cluster)-rw"
		ro:      "\(cluster)-read"
		db:      _t.name
	}]
}

_t:  cnpgdog.topology
_st: cnpgdog.shardedTables
