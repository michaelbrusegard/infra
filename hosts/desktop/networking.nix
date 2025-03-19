{ ... }: {
  networking = {
    firewall = {
      allowedTCPPorts = [ 22 ];
    };
    networkmanager = {
      enable = true;
      dhcp = "dhcpcd";
    };
    dhcpcd.enable = true;
    wireguard.enable = true;
  };
}
