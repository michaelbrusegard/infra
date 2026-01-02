_: {
  networking = {
    wireless.iwd.enable = true;
    networkmanager = {
      enable = true;
      wifi.backend = "iwd";
      dns = "systemd-resolved";
    };
    dhcpcd.enable = false;
    wireguard.enable = true;
  };

  services.avahi.allowInterfaces = ["enp6s0"];
}
