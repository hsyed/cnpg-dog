package cnpgdog

import (
	"github.com/hsyed/cnpg-dog/lib"
	"github.com/hsyed/cnpg-dog/lib/render"
)

// Root composition, separate from the user-facing topology.
// Image pins are injected from flake.nix; see scripts/cue.sh.
_pgdogImage: string @tag(pgdogImage)
_pgImage:    string @tag(pgImage)
_derived: (lib.#Topology & {config: topology}).out
_output: render.#Output & {
	topology:   _derived
	pgdogImage: _pgdogImage
}

namespace:    _output.namespace
manifests:    _output.manifests
secrets:      _output.secrets
credentials:  _output.credentials
assertSchema: _output.assertSchema
