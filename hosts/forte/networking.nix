{config, ...}: {
  networking = {
    wireless.iwd.enable = true;
    networkmanager = {
      enable = true;
      wifi = {
        backend = "iwd";
        powersave = false;
      };
    };
    dhcpcd.enable = false;
  };
  services.netbird = {
    useRoutingFeatures = "client";
    clients.default = {
      autoStart = true;
      port = 51820;
    };
  };

  environment.persistence."/persistent".directories = [
    "/etc/NetworkManager/system-connections"
    config.services.netbird.clients.default.dir.state
  ];
}
