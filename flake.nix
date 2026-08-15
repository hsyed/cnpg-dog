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
            just
            kind
            kubectl
            kubectl-cnpg
            postgresql_17
            jq
            yq-go
          ];

          # Single home for every version pin. Nothing else may hardcode these.
          KIND_NODE_IMAGE = "kindest/node:v1.34.8@sha256:02722c2dedddcfc00febf5d27fbeb9b7b2c14294c82109ff4a85d89ac9ba3256";
          CNPG_MANIFEST = "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.30/releases/cnpg-1.30.0.yaml";
          PGDOG_IMAGE = "ghcr.io/pgdogdev/pgdog:v0.1.44";
          PG_IMAGE = "ghcr.io/cloudnative-pg/postgresql:17";
          CLUSTER_NAME = "cnpg-dog";
          APP_NS = "dog";
        };
      });
}
