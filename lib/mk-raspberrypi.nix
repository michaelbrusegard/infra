inputs: {
  hostname,
  system,
  users,
  hostConfig ? null,
}: let
  resolvedHostConfig =
    if hostConfig != null
    then hostConfig
    else hostname;
in
  inputs.nixos-raspberrypi.lib.nixosSystem {
    inherit system;

    specialArgs = {
      inherit inputs hostname users;
      hostConfig = resolvedHostConfig;
      inherit (inputs) nixos-raspberrypi;
      isWsl = false;
    };

    modules =
      [
        (inputs.self + "/hosts/${resolvedHostConfig}")
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
