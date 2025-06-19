{ config, ... }: {
  networking = {
    firewall = {
      allowedTCPPorts = [ 53 3000 ];
      allowedUDPPorts = [ 51820 53 ];
    };
    nat = {
      enable = true;
      internalInterfaces = [ "wg0" ];
      externalInterface = "eth0";
    };
    wireguard.interfaces.wg0 = {
      ips = [ "10.10.62.1/24" ];
      listenPort = 51820;
      privateKeyFile = config.secrets.leggero.wireguard.privateKeyFile;
      peers = [
        {
          name = "desktop";
          publicKey = config.secrets.leggero.wireguard.peers.desktop.publicKey;
          allowedIPs = [ "10.10.62.2/32" ];
        }
        {
          name = "laptop";
          publicKey = config.secrets.leggero.wireguard.peers.laptop.publicKey;
          allowedIPs = [ "10.10.62.3/32" ];
        }
        {
          name = "tablet";
          publicKey = config.secrets.leggero.wireguard.peers.tablet.publicKey;
          allowedIPs = [ "10.10.62.4/32" ];
        }
        {
          name = "phone";
          publicKey = config.secrets.leggero.wireguard.peers.phone.publicKey;
          allowedIPs = [ "10.10.62.4/32" ];
        }
      ];
    };
  };
}
