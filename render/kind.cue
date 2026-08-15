package render

import (
	"list"
	"github.com/hsyed/cnpg-dog/lib"
)

kindConfig: {
	kind:       "Cluster"
	apiVersion: "kind.x-k8s.io/v1alpha4"
	name:       "cnpg-dog"
	nodes: list.Concat([[
		{role: "control-plane"},
	], [for z in lib.fabric.zones {
		role: "worker"
		labels: "topology.kubernetes.io/zone": z
	}]])
}
