_: {
  boot.kernel.sysctl = {
    "net.ipv6.conf.all.forwarding" = 1;
  };

  networking.firewall = {
    allowedTCPPorts = [6443 6444 2379 2380 10250];
    allowedUDPPorts = [8472];
  };
}
