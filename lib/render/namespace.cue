package render

#Output: {
	topology: _

	_namespace: {
		apiVersion: "v1"
		kind:       "Namespace"
		metadata: {
			name: topology.name
			annotations: "argocd.argoproj.io/sync-wave": "0"
		}
	}
	namespace: _namespace

	// POC credentials, shared by CNPG and PgDog. Export only through the
	// gitignored secrets stream; local tooling reads them from credentials.
	_password: "dogpassword"
	credentials: {
		username: topology.name
		password: _password
	}
	_appSecret: {
		apiVersion: "v1"
		kind:       "Secret"
		type:       "kubernetes.io/basic-auth"
		metadata: {
			name:      "\(topology.name)-app"
			namespace: topology.name
			annotations: "argocd.argoproj.io/sync-wave": "0"
		}
		stringData: credentials
	}
}
