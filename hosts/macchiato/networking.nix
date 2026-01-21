{config, ...}: let
  wanInterface = "enp1s0";
  lanInterfaces = ["enp2s0" "enp3s0" "sfp0"];
in {
  networking = {
    bridges.br0.interfaces = lanInterfaces;

    interfaces = {
      "${wanInterface}".useDHCP = true;
      br0.ipv4.addresses = [
        {
          address = "10.0.186.1";
          prefixLength = 24;
        }
      ];
    };

    nat = {
      enable = true;
      externalInterface = wanInterface;
      internalInterfaces = ["br0" "wg0"];
    };

    firewall = {
      enable = true;

      interfaces.br0.allowedTCPPorts = [53 9090 3000 1883 8080 8581];
      interfaces.br0.allowedUDPPorts = [53 67];

      interfaces.wg0.allowedTCPPorts = [53 9090 3000 1883 8080 8581];
      interfaces.wg0.allowedUDPPorts = [53];

      interfaces."${wanInterface}".allowedUDPPorts = [51820];
    };

    wireguard.interfaces.wg0 = {
      ips = ["10.0.187.1/24"];
      listenPort = 51820;
      inherit (config.secrets.wireguard) privateKeyFile;
      inherit (config.secrets.wireguard) peers;
    };
  };

  services.dnsmasq = {
    enable = true;
    settings = {
      interface = "br0";
      port = 0;
      dhcp-range = "10.0.186.50,10.0.186.254,24h";
      dhcp-option = [
        "3,10.0.186.1"
        "6,10.0.186.1"
      ];
    };
  };

  services.avahi.allowInterfaces = ["br0" "wg0"];
}
