package render

import (
	"list"
	topologyTypes "github.com/hsyed/cnpg-dog/lib/topology"
	"github.com/hsyed/cnpg-dog/lib/topology/upstream"
)

// Every renderer extends this definition; callers supply the derived topology.
#Output: {
	topology:   topologyTypes.#DerivedTopology
	pgdogImage: string
	// Bind cross-file fields to their native types in this lexical scope;
	// their values live in the resource-specific fragments of this definition.
	_namespace: upstream.#Namespace
	_appSecret: upstream.#Secret
	_clusters: [...upstream.#Cluster]
	_pgdogConfigMap:  upstream.#ConfigMap
	_pgdogDeployment: upstream.#Deployment
	_pgdogService:    upstream.#Service
	_pgdogSecret:     upstream.#Secret
	manifests: {
		apiVersion: "v1"
		kind:       "List"
		items: list.Concat([[_namespace], _clusters, [_pgdogConfigMap, _pgdogDeployment, _pgdogService]])
	}
	secrets: {
		apiVersion: "v1"
		kind:       "List"
		items: [_appSecret, _pgdogSecret]
	}
}
