{ ... }: {
  networking.firewall = {
    allowedTCPPorts = [ 6443 2379 2380 10250 ];
    allowedUDPPorts = [ 8472 ];
  };
}
