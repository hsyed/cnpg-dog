package render

#Output: {
	topology: _

	// Native fields pass through unchanged. Shard identity, sync-wave, and the
	// read service are owned by orchestration; contradictory template values
	// (including a template managed.services.additional) fail unification.
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

				// Zone-local replica reads for PgDog, owned by the Cluster.
				if topology.pg.template.spec.instances > 1 {
					managed: services: additional: [{
						selectorType: "ro"
						serviceTemplate: {
							metadata: name:            s.ro
							spec: trafficDistribution: "PreferSameZone"
						}
					}]
				}
			}
		}
	}]
}
