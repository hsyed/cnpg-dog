package render

import "list"

#Output: {
	topology: _
	// Native kind settings pass through. kind validates its own API; we do not
	// maintain a parallel schema for networking, mounts, ports, or node patches.
	kind: {...}
	let options = kind

	// Three synthetic zones are a local fixture, independent of native CNPG
	// scheduling policy. This does not promise to satisfy arbitrary affinity.
	_workerCount: list.Max([3, topology.pg.template.spec.instances, topology.dog.replicas])
	_kindZones: list.Repeat(["a", "b", "c"], _workerCount)
	kindConfig: {
		options
		kind:       "Cluster"
		apiVersion: "kind.x-k8s.io/v1alpha4"
		if options.name == _|_ {
			name: "cnpg-dog"
		}
		if options.nodes == _|_ {
			nodes: list.Concat([[
				{role: "control-plane"},
			], [for i in list.Range(0, _workerCount, 1) {
				role: "worker"
				labels: "topology.kubernetes.io/zone": _kindZones[i]
			}]])
		}
	}
}
