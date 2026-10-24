package cnpgdog

import (
	"github.com/hsyed/cnpg-dog/lib"
	"github.com/hsyed/cnpg-dog/lib/render"
)

// Root composition, separate from the user-facing topology.
_pgdogImage: string @tag(pgdogImage)
_derived: (lib.#Topology & {config: topology}).out
let kindOptions = kind
_output: render.#Output & {
	topology:   _derived
	pgdogImage: _pgdogImage
	kind:       kindOptions
}

kindConfig:   _output.kindConfig
namespace:    _output.namespace
manifests:    _output.manifests
secrets:      _output.secrets
assertSchema: _output.assertSchema
