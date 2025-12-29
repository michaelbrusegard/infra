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
    isWsl = false;
  };

  modules =
    [ (inputs.self + "/hosts/${hostname}") ]
    ++ map
      (user: inputs.self + "/users/${user}/darwin.nix")
      users;
}
