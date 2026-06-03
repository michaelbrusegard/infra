{
  config,
  lib,
  isWsl,
  ...
}: {
  # systemd-resolved is required so NetBird can register per-domain (split)
  services.resolved.enable = true;

  # NetworkManager must defer DNS to systemd-resolved, otherwise it rewrites
  # /etc/resolv.conf with the LAN resolver and clobbers NetBird's split DNS.
  networking.networkmanager.dns = "systemd-resolved";

  services.netbird = {
    useRoutingFeatures = "client";
    clients.default = {
      port = 51820;
      config = lib.mkForce {
        WgIface = config.services.netbird.clients.default.interface;
        WgPort = config.services.netbird.clients.default.port;
      };
    };
  };

  users.users.michaelbrusegard.extraGroups = [
    config.services.netbird.clients.default.user.group
  ];

  environment.persistence = lib.optionalAttrs (!isWsl) {
    "/persistent".directories = [
      config.services.netbird.clients.default.dir.state
    ];
  };
}
