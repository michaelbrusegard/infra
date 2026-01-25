{name, ...}: {
  networking = {
    hostName = name;
    firewall.enable = true;
  };
}
