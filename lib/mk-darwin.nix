inputs:

{ hostname, system, users }:

let
  pkgs = import inputs.nixpkgs {
    inherit system;
    overlays = inputs.self.overlays.default;
  };
in
inputs.nix-darwin.lib.darwinSystem {
  inherit system pkgs;

  specialArgs = {
    inherit inputs users hostname;
  };

  modules =
    [ ../hosts/${hostname} ]
    ++ map
      (u: ../../users/${u}/darwin.nix)
      users;
}
