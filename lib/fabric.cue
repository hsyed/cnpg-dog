package lib

import (
	"list"
	"github.com/hsyed/cnpg-dog:cnpgdog"
)

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
