inputs: {
  name,
  system,
  users,
  hostConfig ? null,
  platform ? null,
}: let
  resolvedHostConfig =
    if hostConfig != null
    then hostConfig
    else name;
in
  inputs.nixpkgs.lib.nixosSystem {
    inherit system;

    specialArgs = {
      inherit inputs name users;
      hostConfig = resolvedHostConfig;
      isWsl = platform == "wsl";
    };

    modules =
      [
        (inputs.self + "/hosts/${resolvedHostConfig}")
        {
          imports = [
            inputs.nix-secrets.nixosModules.secrets
          ];
        }
      ]
      ++ map
      (user: inputs.self + "/users/${user}/nixos.nix")
      users;
  }
