package cnpgdog

// ---------------------------------------------------------------------------
// Topology model. The knobs and the single derivation live here.
// ---------------------------------------------------------------------------

// #Topology is the complete set of knobs for the fabric.
#Topology: {
	name:                         string
	shards:                       int & >=1
	zones: [...string] & [_, ...] // at least one zone
	pgVersion:                    string
	storage:                      string
}

// #Shard is a single derived shard. Every name in the system comes from here;
// nothing else may build a service name by concatenation.
#Shard: {
	id:      int & >=0
	cluster: string // CNPG Cluster metadata.name
	rw:      string // CNPG-owned primary service
	ro:      string // our read service, PreferClose
	db:      string // database name
}

// #ShardedTable is the one fact PgDog needs about the schema. It is consumed
// twice: by pgdog.toml and by the generated schema assertion.
#ShardedTable: {
	table:    string
	column:   string
	dataType: "bigint" | "uuid" | "varchar" | "vector"
}

#Fabric: {
	topology: #Topology
	zones: [...string]
	shards: [...#Shard]
	shardedTables: [...#ShardedTable]
}

// ---------------------------------------------------------------------------
// POC-grade partial schema. Intentionally incomplete: it constrains only the
// fields this project sets. Authoritative validation is `kubectl apply
// --dry-run=server`. See the deviation note in the implementation plan.
// ---------------------------------------------------------------------------

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
