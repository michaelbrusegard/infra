inputs: let
  inherit (inputs) nixpkgs;

  forAllSystems = nixpkgs.lib.genAttrs [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
  ];

  merge =
    builtins.foldl' (a: b: a // b) {};

  mkSystem =
    import ./mk-system.nix inputs;

  mkNode =
    import ./mk-node.nix inputs;

  mkColmenaMeta =
    import ./mk-colmena-meta.nix inputs;

  mkCluster = {
    names,
    system,
    users,
    hostConfig,
    platform ? null,
  }:
    merge (
      map
      (name:
        mkSystem {
          inherit name system users platform hostConfig;
        })
      names
    );

  exportModules =
    import ./export-modules.nix nixpkgs.lib;
in {
  inherit
    forAllSystems
    merge
    mkSystem
    mkNode
    mkColmenaMeta
    mkCluster
    exportModules
    ;
}
