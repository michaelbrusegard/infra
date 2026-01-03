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
  inputs.nix-darwin.lib.darwinSystem {
    inherit system;

    specialArgs = {
      inherit inputs name users;
      hostConfig = resolvedHostConfig;
      isWsl = false;
    };

    modules =
      [
        (inputs.self + "/hosts/${resolvedHostConfig}")
        {
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
