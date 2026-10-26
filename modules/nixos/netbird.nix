{
  config,
  lib,
  inputs,
  isWsl,
  users,
  ...
}: {
  # The client package comes from unstable, and 26.05's module rewrites the
  # desktop file NetBird shipped before its Wails UI. Use the matching module.
  disabledModules = ["services/networking/netbird.nix"];
  imports = ["${inputs.nixpkgs-unstable}/nixos/modules/services/networking/netbird.nix"];

  # Split DNS needs systemd-resolved, which hosts enable themselves: a router
  # running its own resolver on port 53 wants nothing to do with it.
  services.netbird = {
    useRoutingFeatures = lib.mkDefault "client";
    clients.default = {
      port = 51820;
      config = {
        WgIface = lib.mkForce config.services.netbird.clients.default.interface;
        WgPort = lib.mkForce config.services.netbird.clients.default.port;
      };
    };
  };

  users.users = lib.optionalAttrs (builtins.elem "michaelbrusegard" users) {
    michaelbrusegard.extraGroups = [
      config.services.netbird.clients.default.user.group
    ];
  };

  environment.persistence = lib.optionalAttrs (!isWsl) {
    "/persistent".directories = [
      config.services.netbird.clients.default.dir.state
    ];
  };
}
