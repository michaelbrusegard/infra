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
    nixos-raspberrypi = inputs.nixos-raspberrypi;
  };

  modules =
    [ (inputs.self + "/hosts/${hostname}") ]
    ++ map
      (user: inputs.self + "/users/${user}/nixos.nix")
      users;
}
