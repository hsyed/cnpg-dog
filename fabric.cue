package cnpgdog

import "list"

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

_t:  topology
_st: shardedTables
