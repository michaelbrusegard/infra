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

  exportModules = dir: let
    files = builtins.readDir dir;
    validFiles =
      nixpkgs.lib.filterAttrs
      (name: type:
        type
        == "regular"
        && nixpkgs.lib.hasSuffix ".nix" name)
      files;
    nameFromPath = name: nixpkgs.lib.removeSuffix ".nix" name;
  in
    nixpkgs.lib.mapAttrs'
    (name: _: {
      name = nameFromPath name;
      value = import (dir + "/${name}");
    })
    validFiles;
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
