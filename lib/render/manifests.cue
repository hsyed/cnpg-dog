package render

import (
	"list"
	"github.com/hsyed/cnpg-dog/lib/schema"
)

// Every renderer extends this definition; callers supply the derived topology.
#Output: {
	topology:   schema.#DerivedTopology
	pgdogImage: string
	// Bind cross-file fields in this lexical scope; their values live in the
	// resource-specific fragments of this same definition.
	_namespace: schema.#Namespace
	_appSecret: schema.#Secret
	_clusters: [...schema.#CNPGCluster]
	_readServices: [...schema.#Service]
	_pgdogConfigMap:  schema.#ConfigMap
	_pgdogDeployment: schema.#Deployment
	_pgdogService:    schema.#Service
	_pgdogSecret:     schema.#Secret
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
