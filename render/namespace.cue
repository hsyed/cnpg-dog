package render

import (
	"github.com/hsyed/cnpg-dog:cnpgdog"
	"github.com/hsyed/cnpg-dog/schema"
)

_namespace: schema.#Namespace & {
	apiVersion: "v1"
	kind:       "Namespace"
	metadata: {
		name: cnpgdog.fabric.topology.name
		annotations: "argocd.argoproj.io/sync-wave": "0"
	}
}

// Exported alone so `just apply` can create it before the secrets (which live
// in it) and before the clusters (which reference it).
namespace: _namespace

// App credentials. Rendered into the gitignored secrets stream, never committed.
_appSecret: schema.#Secret & {
	apiVersion: "v1"
	kind:       "Secret"
	type:       "kubernetes.io/basic-auth"
	metadata: {
		name:      "\(cnpgdog.fabric.topology.name)-app"
		namespace: cnpgdog.fabric.topology.name
		annotations: "argocd.argoproj.io/sync-wave": "0"
	}
	stringData: {
		username: cnpgdog.fabric.topology.name
		password: "dogpassword" // POC-grade. ExternalSecrets would replace this.
	}
}
