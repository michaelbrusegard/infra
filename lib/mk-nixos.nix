inputs:

{ hostname, system, users }:

inputs.nixpkgs.lib.nixosSystem {
  inherit system;

  specialArgs = {
    inherit inputs hostname users;
    isWsl = builtins.pathExists /proc/sys/fs/binfmt_misc/WSLInterop;
  };

  modules =
    [
      (inputs.self + "/hosts/${hostname}")
      {
        nixpkgs.overlays = inputs.self.overlays.default;
        imports = [
          inputs.nix-secrets.nixosModules.secrets
        ];
      }
    ]
    ++ map
      (user: inputs.self + "/users/${user}/nixos.nix")
      users;
}
