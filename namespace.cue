package cnpgdog

_namespace: #Namespace & {
	apiVersion: "v1"
	kind:       "Namespace"
	metadata: {
		name: fabric.topology.name
		annotations: "argocd.argoproj.io/sync-wave": "0"
	}
}

// App credentials. Rendered into the gitignored secrets stream, never committed.
_appSecret: #Secret & {
	apiVersion: "v1"
	kind:       "Secret"
	type:       "kubernetes.io/basic-auth"
	metadata: {
		name:      "\(fabric.topology.name)-app"
		namespace: fabric.topology.name
		annotations: "argocd.argoproj.io/sync-wave": "0"
	}
	stringData: {
		username: fabric.topology.name
		password: "dogpassword" // POC-grade. ExternalSecrets would replace this.
	}
}
