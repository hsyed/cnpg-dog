package cnpgdog

import "list"

// Applied output, safe to commit.
manifests: {
	apiVersion: "v1"
	kind:       "List"
	items: list.Concat([[_namespace], _clusters, _readServices])
}

// Gitignored. Applied but never committed.
secrets: {
	apiVersion: "v1"
	kind:       "List"
	items: [_appSecret]
}
