{ ... }: {
  networking = {
    firewall = {
      allowedTCPPorts = [ 22 ];
    };
    wireless.iwd.enable = true;
    networkmanager = {
      enable = true;
      dhcp = "dhcpcd";
      wifi.backend = "iwd";
    };
    dhcpcd.enable = true;
    wireguard.enable = true;
  };
}
