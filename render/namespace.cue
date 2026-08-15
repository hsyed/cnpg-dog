package render

import "github.com/hsyed/cnpg-dog/lib"

_namespace: lib.#Namespace & {
	apiVersion: "v1"
	kind:       "Namespace"
	metadata: {
		name: lib.fabric.shardedCluster.name
		annotations: "argocd.argoproj.io/sync-wave": "0"
	}
}

// Exported alone so `just apply` can create it before the secrets (which live
// in it) and before the clusters (which reference it).
namespace: _namespace

// App credentials. Rendered into the gitignored secrets stream, never committed.
_appSecret: lib.#Secret & {
	apiVersion: "v1"
	kind:       "Secret"
	type:       "kubernetes.io/basic-auth"
	metadata: {
		name:      "\(lib.fabric.shardedCluster.name)-app"
		namespace: lib.fabric.shardedCluster.name
		annotations: "argocd.argoproj.io/sync-wave": "0"
	}
	stringData: {
		username: lib.fabric.shardedCluster.name
		password: "dogpassword" // POC-grade. ExternalSecrets would replace this.
	}
}
