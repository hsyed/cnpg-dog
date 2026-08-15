package schema

// POC-grade partial schema. Intentionally incomplete: it constrains only the
// fields this project sets. Authoritative validation is `kubectl apply
// --dry-run=server`. See the deviation note in the implementation plan.

#Meta: {
	name:       string
	namespace?: string
	labels?: [string]:      string
	annotations?: [string]: string
}

#Namespace: {
	apiVersion: string
	kind:       "Namespace"
	metadata:   #Meta
	...
}

#ConfigMap: {
	apiVersion: string
	kind:       "ConfigMap"
	metadata:   #Meta
	data?: [string]: string
	...
}

#Secret: {
	apiVersion: string
	kind:       "Secret"
	type?:      string
	metadata:   #Meta
	stringData?: [string]: string
	data?: [string]:       string
	...
}

#Service: {
	apiVersion: string
	kind:       "Service"
	metadata:   #Meta
	spec: {
		type?:                string
		trafficDistribution?: string
		selector?: [string]: string
		ports?: [...{
			name?:       string
			port:        int
			targetPort?: int
		}]
	}
	...
}

#Deployment: {
	apiVersion: string
	kind:       "Deployment"
	metadata:   #Meta
	spec: {
		replicas?: int
		selector?: matchLabels: [string]: string
		template?: {
			metadata?: labels: [string]: string
			spec?: {...}
		}
		...
	}
	...
}
