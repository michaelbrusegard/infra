inputs: {
  hostname,
  system,
  users,
}:
inputs.nixos-raspberrypi.lib.nixosSystem {
  inherit system;

  specialArgs = {
    inherit inputs hostname users;
    inherit (inputs) nixos-raspberrypi;
  };

  modules =
    [
      (inputs.self + "/hosts/${hostname}")
      {
        nixpkgs.overlays = [inputs.self.overlays.default];
        imports = [
          inputs.nix-secrets.nixosModules.secrets
        ];
      }
    ]
    ++ map
    (user: inputs.self + "/users/${user}/nixos.nix")
    users;
}
