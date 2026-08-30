{
  config,
  lib,
  isWsl,
  users,
  ...
}: {
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
