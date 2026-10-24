package schema

import "github.com/hsyed/cnpg-dog/lib/schema/upstream"

// Native upstream types, generated from the release pins in flake.nix.
// Server-side dry-run still checks CEL, admission, and cluster-specific rules.
#Namespace:   upstream.#Namespace
#ConfigMap:   upstream.#ConfigMap
#Secret:      upstream.#Secret
#Service:     upstream.#Service
#Deployment:  upstream.#Deployment
#CNPGCluster: upstream.#Cluster
