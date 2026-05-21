_: {
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
      autoStart = false;
      port = 51820;
    };
  };
}
