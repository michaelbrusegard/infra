inputs: {
  name,
  system,
  users,
  hostConfig ? null,
}: let
  resolvedHostConfig =
    if hostConfig != null
    then hostConfig
    else name;
in
  inputs.nixos-raspberrypi.lib.nixosSystem {
    inherit system;
    inherit (inputs) nixpkgs;

    specialArgs = {
      inherit inputs name users;
      hostConfig = resolvedHostConfig;
      inherit (inputs) nixos-raspberrypi;
      isWsl = false;
    };

    modules =
      [
        (inputs.self + "/hosts/${resolvedHostConfig}")
        {
          imports = [
            inputs.secrets.nixosModules.secrets
          ];
        }
      ]
      ++ map
      (user: inputs.self + "/users/${user}/nixos.nix")
      users;
  }
