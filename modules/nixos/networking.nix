{hostname, ...}: {
  networking = {
    hostName = hostname;
    enableIPv6 = true;
    firewall.enable = true;
  };
}
