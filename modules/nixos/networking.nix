{name, ...}: {
  networking = {
    hostName = name;
    enableIPv6 = true;
    firewall.enable = true;
  };
}
