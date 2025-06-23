{ config, ... }: {
  networking = {
    firewall = {
      allowedTCPPorts = [ 53 9090 3000 8123 5580 8081 8082 80 443 ];
      allowedUDPPorts = [ 51820 53 ];
    };
    nat = {
      enable = true;
      internalInterfaces = [ "wg0" ];
      externalInterface = "end0";
    };
    wireguard.interfaces.wg0 = {
      ips = [ "10.0.62.1/24" ];
      listenPort = 51820;
      privateKeyFile = config.secrets.leggero.wireguard.privateKeyFile;
      peers = config.secrets.leggero.wireguard.peers;
      postSetup = ''
        ip link set wg0 multicast on
      '';
    };
  };
}
