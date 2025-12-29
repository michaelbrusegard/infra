inputs:

{ hostname, system, users }:

let
  pkgs = import inputs.nixpkgs {
    inherit system;
    overlays = inputs.self.overlays.default;
  };
in
inputs.nixos-raspberrypi.lib.nixosSystem {
  inherit system pkgs;

  specialArgs = {
    inherit inputs hostname users;
  };

  modules =
    [ ../hosts/${hostname} ]
    ++ map
      (u: ../../users/${u}/nixos.nix)
      users;
}
