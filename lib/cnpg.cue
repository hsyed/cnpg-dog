package lib

// The `postgresql` block is copied verbatim from docs/reference/cnpg-placement.md:
// `method: first` yields a single observable `sync` replica (method `any` yields
// `quorum` and no single sync replica — see that file).

_clusters: [for s in fabric.shards {
	#CNPGCluster & {
		apiVersion: "postgresql.cnpg.io/v1"
		kind:       "Cluster"
		metadata: {
			name:      s.cluster
			namespace: fabric.shardedCluster.name
			annotations: "argocd.argoproj.io/sync-wave": "1"
		}
		spec: {
			instances: len(fabric.zones)
			imageName: "ghcr.io/cloudnative-pg/postgresql:\(fabric.shardedCluster.pgVersion)"
			storage: size: fabric.shardedCluster.storage
			bootstrap: initdb: {
				database: s.db
				owner:    s.db
				secret: name: "\(fabric.shardedCluster.name)-app"
			}
			postgresql: {
				synchronous: {
					method: "first"
					number: 1
				}
				syncReplicaElectionConstraint: {
					enabled: true
					nodeLabelsAntiAffinity: ["topology.kubernetes.io/zone"]
				}
			}
			topologySpreadConstraints: [{
				maxSkew:           1
				topologyKey:       "topology.kubernetes.io/zone"
				whenUnsatisfiable: "DoNotSchedule"
				labelSelector: matchLabels: "cnpg.io/cluster": s.cluster
			}]
		}
	}
}]

// Read services we own, so we can set trafficDistribution ourselves rather
// than depending on CNPG's managed-services API. The replica label key is the
// one verified in docs/reference/cnpg-placement.md.
_readServices: [for s in fabric.shards {
	#Service & {
		apiVersion: "v1"
		kind:       "Service"
		metadata: {
			name:      s.ro
			namespace: fabric.shardedCluster.name
			annotations: "argocd.argoproj.io/sync-wave": "1"
		}
		spec: {
			type:                "ClusterIP"
			trafficDistribution: "PreferSameZone"
			selector: {
				"cnpg.io/cluster":      s.cluster
				"cnpg.io/instanceRole": "replica"
			}
			ports: [{
				name:       "postgres"
				port:       5432
				targetPort: 5432
			}]
		}
	}
}]
