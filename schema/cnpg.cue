package schema

// POC-grade partial schema. Intentionally incomplete: it constrains only the
// fields this project sets. Authoritative validation is `kubectl apply
// --dry-run=server`. See the deviation note in the implementation plan.

#CNPGCluster: {
	apiVersion: string
	kind:       "Cluster"
	metadata:   #Meta
	spec: {
		instances: int
		imageName: string
		storage?: size: string
		...
	}
	...
}
