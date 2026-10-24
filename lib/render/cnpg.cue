package render

import "github.com/hsyed/cnpg-dog/lib/schema"

#Output: {
	topology: _

	// Native fields pass through unchanged. Shard identity and sync-wave are
	// owned by orchestration; contradictory template values fail unification.
	_clusters: [for s in topology.shards {
		topology.pg.template & {
			metadata: {
				name:      s.cluster
				namespace: topology.name
				annotations: "argocd.argoproj.io/sync-wave": "1"
			}
			spec: {
				// Explicit native bootstrap configurations are not rewritten.
				// Their database/user/credentials must match the PgDog setup.
				if topology.pg.template.spec.bootstrap == _|_ {
					bootstrap: initdb: {
						database: s.db
						owner:    s.db
						secret: name: "\(topology.name)-app"
					}
				}
			}
		}
	}]

	_readServices: [for s in topology.shards if topology.pg.template.spec.instances > 1 {
		schema.#Service & {
			apiVersion: "v1"
			kind:       "Service"
			metadata: {
				name:      s.ro
				namespace: topology.name
				annotations: "argocd.argoproj.io/sync-wave": "1"
			}
			spec: {
				type:                "ClusterIP"
				trafficDistribution: "PreferSameZone"
				selector: {
					"cnpg.io/cluster":      s.cluster
					"cnpg.io/instanceRole": "replica"
				}
				ports: [{name: "postgres", port: 5432, targetPort: 5432}]
			}
		}
	}]
}
