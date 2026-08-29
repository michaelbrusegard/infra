{
  config,
  lib,
  isWsl,
  users,
  ...
}: {
  # systemd-resolved is required so NetBird can register per-domain (split)
  services.resolved.enable = true;

  # NetworkManager must defer DNS to systemd-resolved, otherwise it rewrites
  # /etc/resolv.conf with the LAN resolver and clobbers NetBird's split DNS.
  networking.networkmanager.dns = "systemd-resolved";

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
