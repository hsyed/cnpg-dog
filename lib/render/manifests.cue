package render

import (
	"list"
	topologyTypes "github.com/hsyed/cnpg-dog/lib/topology"
)

// Every renderer extends this definition; callers supply the derived topology.
#Output: {
	topology:   topologyTypes.#DerivedTopology
	pgdogImage: string
	// Bind cross-file fields in this lexical scope; their values live in the
	// resource-specific fragments of this same definition.
	_namespace: topologyTypes.#Namespace
	_appSecret: topologyTypes.#Secret
	_clusters: [...topologyTypes.#CNPGCluster]
	_readServices: [...topologyTypes.#Service]
	_pgdogConfigMap:  topologyTypes.#ConfigMap
	_pgdogDeployment: topologyTypes.#Deployment
	_pgdogService:    topologyTypes.#Service
	_pgdogSecret:     topologyTypes.#Secret
	manifests: {
		apiVersion: "v1"
		kind:       "List"
		items: list.Concat([[_namespace], _clusters, _readServices, [_pgdogConfigMap, _pgdogDeployment, _pgdogService]])
	}
	secrets: {
		apiVersion: "v1"
		kind:       "List"
		items: [_appSecret, _pgdogSecret]
	}
}
