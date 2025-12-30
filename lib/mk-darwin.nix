inputs:

{ hostname, system, users }:

inputs.nix-darwin.lib.darwinSystem {
  inherit system;

  specialArgs = {
    inherit inputs users hostname;
    isWsl = false;
  };

  modules =
    [
      (inputs.self + "/hosts/${hostname}")
      { nixpkgs.overlays = inputs.self.overlays.default; }
    ]
    ++ map
      (user: inputs.self + "/users/${user}/darwin.nix")
      users;
}
