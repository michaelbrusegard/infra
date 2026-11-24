{
  inputs,
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types;

  isDarwin = host: lib.hasSuffix "-darwin" host.system;
  isRaspberryPi = host: host.platform == "raspberrypi";

  specialArgs = name: host: {
    inherit name;
    inherit (host) users;
    inherit (inputs) nixos-raspberrypi;
    isWsl = host.platform == "wsl";
  };

  modulesFor = class: host:
    [
      config.flake.modules.${class}.${host.configuration}
      inputs.secrets."${class}Modules".${host.secrets}
    ]
    ++ map (user: config.flake.modules.${class}.${user}) host.users;

  mkNixos = name: host:
    (
      if isRaspberryPi host
      then
        args:
          inputs.nixos-raspberrypi.lib.nixosSystem (args // {inherit (inputs) nixpkgs;})
      else inputs.nixpkgs.lib.nixosSystem
    ) {
      inherit (host) system;
      specialArgs = specialArgs name host;
      modules = modulesFor "nixos" host;
    };

  mkDarwin = name: host:
    inputs.nix-darwin.lib.darwinSystem {
      inherit (host) system;
      specialArgs = specialArgs name host;
      modules = modulesFor "darwin" host ++ [inputs.brew-nix.darwinModules.default];
    };

  # Colmena evaluates nodes itself instead of calling
  # nixos-raspberrypi.lib.nixosSystem, so Raspberry Pi nodes need the modules
  # that wrapper would have added.
  raspberryPiModules = [
    inputs.nixos-raspberrypi.nixosModules.nixpkgs-rpi
    inputs.nixos-raspberrypi.lib.inject-overlays
    inputs.nixos-raspberrypi.nixosModules.trusted-nix-caches
  ];

  mkNode = name: host: {
    deployment = {
      targetHost = "deploy-${name}";
      targetUser = "deploy";
      inherit (host.deploy) buildOnTarget;
    };
    nixpkgs.system = host.system;
    imports =
      modulesFor "nixos" host
      ++ lib.optionals (isRaspberryPi host) raspberryPiModules;
  };

  nixosHosts = lib.filterAttrs (_: host: !isDarwin host) config.hosts;
  darwinHosts = lib.filterAttrs (_: isDarwin) config.hosts;
  deployHosts = lib.filterAttrs (_: host: host.deploy != null) config.hosts;
in {
  options.hosts = mkOption {
    default = {};
    type = types.attrsOf (types.submodule ({
      name,
      config,
      ...
    }: {
      options = {
        system = mkOption {type = types.str;};
        users = mkOption {type = types.listOf types.str;};
        configuration = mkOption {
          type = types.str;
          default = name;
        };
        secrets = mkOption {
          type = types.str;
          default = config.configuration;
        };
        platform = mkOption {
          type = types.nullOr (types.enum ["wsl" "raspberrypi"]);
          default = null;
        };
        deploy = mkOption {
          type = types.nullOr (types.submodule {
            options.buildOnTarget = mkOption {
              type = types.bool;
              default = false;
            };
          });
          default = null;
        };
      };
    }));
  };

  config.flake = {
    nixosConfigurations = lib.mapAttrs mkNixos nixosHosts;
    darwinConfigurations = lib.mapAttrs mkDarwin darwinHosts;
    colmena =
      {
        meta = {
          allowApplyAll = false;
          nixpkgs = import inputs.nixpkgs {
            system = "x86_64-linux";
            config.allowUnfree = true;
            overlays = [inputs.self.overlays.default];
          };
          nodeSpecialArgs = lib.mapAttrs specialArgs deployHosts;
        };
      }
      // lib.mapAttrs mkNode deployHosts;
  };
}
