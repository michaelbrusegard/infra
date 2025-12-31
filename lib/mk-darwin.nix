inputs: {
  hostname,
  system,
  users,
}:
inputs.nix-darwin.lib.darwinSystem {
  inherit system;

  specialArgs = {
    inherit inputs users hostname;
    isWsl = false;
  };

  modules =
    [
      (inputs.self + "/hosts/${hostname}")
      {
        nixpkgs.overlays = [ inputs.self.overlays.default ];
        imports = [
          inputs.nix-secrets.darwinModules.secrets
          inputs.brew-nix.darwinModules.default
        ];
      }
    ]
    ++ map
    (user: inputs.self + "/users/${user}/darwin.nix")
    users;
}
