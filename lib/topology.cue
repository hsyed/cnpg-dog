package lib

import (
	"list"
	"github.com/hsyed/cnpg-dog/lib/schema"
)

// Pure derivation: the caller supplies configuration; libraries never import
// the root package or depend on a particular deployment.
#Topology: {
	config: schema.#Topology
	out: schema.#DerivedTopology & {
		name: config.name
		pg:   config.pg
		dog:  config.dog
		shards: [for i in list.Range(0, config.pg.shards, 1) {
			id:      i
			cluster: "\(config.name)-s\(i)"
			rw:      "\(cluster)-rw"
			ro:      "\(cluster)-read"
			db:      config.name
		}]
	}
}
