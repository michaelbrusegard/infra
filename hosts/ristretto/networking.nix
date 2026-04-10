_: {
  networking = {
    wireless.iwd.enable = true;
    networkmanager = {
      enable = true;
      wifi.backend = "iwd";
    };
    dhcpcd.enable = false;
  };
  services.netbird.useRoutingFeatures = "client";
}
