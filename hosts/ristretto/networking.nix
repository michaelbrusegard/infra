{config, ...}: {
  networking = {
    wireless.iwd.enable = true;
    networkmanager = {
      enable = true;
      wifi.backend = "iwd";
    };
    dhcpcd.enable = false;
    interfaces.enp6s0.wakeOnLan.enable = true;
  };
  services.netbird = {
    useRoutingFeatures = "client";
    clients.default = {
      autoStart = true;
      port = 51820;
    };
  };

  users.users.michaelbrusegard.extraGroups = [
    config.services.netbird.clients.default.user.group
  ];

  environment.persistence."/persistent".directories = [
    "/etc/NetworkManager/system-connections"
    config.services.netbird.clients.default.dir.state
  ];
}
