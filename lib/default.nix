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

  mkColmena = specs: let
    nodes = map mkNode specs;
  in
    merge (
      [
        (mkColmenaMeta {
          nodeSpecialArgs =
            merge (map (n: {${n.name} = n.specialArgs;}) nodes);
        })
      ]
      ++ map (n: n.node) nodes
    );

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
    mkColmena
    mkCluster
    exportModules
    ;
}
