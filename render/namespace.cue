package render

import (
	"github.com/hsyed/cnpg-dog/model"
	"github.com/hsyed/cnpg-dog/schema"
)

_namespace: schema.#Namespace & {
	apiVersion: "v1"
	kind:       "Namespace"
	metadata: {
		name: model.fabric.topology.name
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
		name:      "\(model.fabric.topology.name)-app"
		namespace: model.fabric.topology.name
		annotations: "argocd.argoproj.io/sync-wave": "0"
	}
	stringData: {
		username: model.fabric.topology.name
		password: "dogpassword" // POC-grade. ExternalSecrets would replace this.
	}
}
