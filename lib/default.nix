inputs:
let
  nixpkgs = inputs.nixpkgs;

  forAllSystems =
    nixpkgs.lib.genAttrs [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];

  merge =
    builtins.foldl' (a: b: a // b) { };

  mkSystem =
    import ./mk-system.nix inputs;

  mkCluster =
    { hostnames, system, users, platform ? null }:
      merge (map
        (hostname:
          mkSystem {
            inherit hostname system users platform;
          })
        hostnames
      );
in
{
  inherit
    forAllSystems
    merge
    mkSystem
    mkCluster;
}
