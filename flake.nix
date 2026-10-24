{
  description = "CNPG + PgDog sharding POC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            cue
            curl
            just
            kind
            kubectl
            kubectl-cnpg
            postgresql_18
            jq
            yq-go
          ];

          # Single home for every version pin. Nothing else may hardcode these.
          KIND_NODE_IMAGE = "kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5";
          CNPG_MANIFEST = "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.30/releases/cnpg-1.30.0.yaml";
          PGDOG_IMAGE = "ghcr.io/pgdogdev/pgdog:v0.1.53";
          PG_IMAGE = "ghcr.io/cloudnative-pg/postgresql:18.4";
          APP_NS = "dog";
        };
      });
}
