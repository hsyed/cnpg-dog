package render

import "github.com/hsyed/cnpg-dog/lib/schema"

#Output: {
	topology: _

	_namespace: schema.#Namespace & {
		apiVersion: "v1"
		kind:       "Namespace"
		metadata: {
			name: topology.name
			annotations: "argocd.argoproj.io/sync-wave": "0"
		}
	}
	namespace: _namespace

	// POC credentials. Export only through the gitignored secrets stream.
	_appSecret: schema.#Secret & {
		apiVersion: "v1"
		kind:       "Secret"
		type:       "kubernetes.io/basic-auth"
		metadata: {
			name:      "\(topology.name)-app"
			namespace: topology.name
			annotations: "argocd.argoproj.io/sync-wave": "0"
		}
		stringData: {
			username: topology.name
			password: "dogpassword"
		}
	}
}
