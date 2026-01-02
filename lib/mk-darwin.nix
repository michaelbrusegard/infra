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
  inputs.nix-darwin.lib.darwinSystem {
    inherit system;

    specialArgs = {
      inherit inputs users hostname;
      hostConfig = resolvedHostConfig;
      isWsl = false;
    };

    modules =
      [
        (inputs.self + "/hosts/${resolvedHostConfig}")
        {
          nixpkgs.overlays = [inputs.self.overlays.default];
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
