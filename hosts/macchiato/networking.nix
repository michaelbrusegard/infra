{ config, ... }: {
  networking = {
    firewall = {
      allowedTCPPorts = [ 53 9090 3000 1883 8080 8581 ];
      allowedUDPPorts = [ 51820 53 ];
    };
    nat = {
      enable = true;
      internalInterfaces = [ "wg0" ];
      externalInterface = "end0";
    };
    wireguard.interfaces.wg0 = {
      ips = [ "10.10.187.1/24" ];
      listenPort = 51820;
      privateKeyFile = config.secrets.macchiato.wireguard.privateKeyFile;
      peers = config.secrets.leggero.wireguard.peers;
      postSetup = ''
        ip link set wg0 multicast on
      '';
    };
  };
}
