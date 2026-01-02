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
  inputs.nixpkgs.lib.nixosSystem {
    inherit system;

    specialArgs = {
      inherit inputs hostname users;
      hostConfig = resolvedHostConfig;
      isWsl = builtins.pathExists /proc/sys/fs/binfmt_misc/WSLInterop;
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
