{ config, ... }: {
  networking = {
    firewall = {
      allowedTCPPorts = config.secrets.desktopSshPorts;
    };
    wireless.iwd.enable = true;
    networkmanager = {
      enable = true;
      wifi.backend = "iwd";
    };
    dhcpcd.enable = false;
    wireguard.enable = true;
  };
}
