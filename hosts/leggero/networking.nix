{ config, ... }: {
  networking = {
    firewall = {
      allowedTCPPorts = [ 53 3000 ];
      allowedUDPPorts = [ 51820 53 ];
    };
    nat = {
      enable = true;
      internalInterfaces = [ "wg0" ];
      externalInterface = "end0";
    };
    wireguard.interfaces.wg0 = {
      ips = [ "10.10.62.1/24" ];
      listenPort = 51820;
      privateKeyFile = config.secrets.leggero.wireguard.privateKeyFile;
      peers = config.secrets.leggero.wireguard.peers;
    };
  };
}
