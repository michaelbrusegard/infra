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

      interfaces = {
        br0 = {
          allowedTCPPorts = [53 9090 3000 1883 8080 8581 6443];
          allowedUDPPorts = [53 67];
        };

        wg0 = {
          allowedTCPPorts = [53 9090 3000 1883 8080 8581 6443];
          allowedUDPPorts = [53];
        };

        "${wanInterface}" = {
          allowedTCPPorts = [80 443];
          allowedUDPPorts = [51820];
        };
      };
    };

    wireguard.interfaces.wg0 = {
      ips = ["10.0.187.1/24"];
      listenPort = 51820;
      inherit (config.secrets.wireguard) privateKeyFile;
      inherit (config.secrets.wireguard) peers;
    };
  };

  services = {
    dnsmasq = {
      enable = true;
      settings = {
        interface = "br0";
        port = 0;
        dhcp-range = "10.0.186.50,10.0.186.254,24h";
        dhcp-option = [
          "3,10.0.186.1"
          "6,10.0.186.1"
        ];
        dhcp-host = [
          "00:00:00:00:00:00,10.0.186.18,espresso-0"
          "00:00:00:00:00:00,10.0.186.19,espresso-1"
          "00:00:00:00:00:00,10.0.186.20,espresso-2"
        ];
      };
    };

    haproxy = {
      enable = true;
      config = ''
        global
          maxconn 4096

        defaults
          mode tcp
          timeout client 30s
          timeout server 30s
          timeout connect 5s

        frontend k3s_api
          bind *:6443
          default_backend k3s_servers
        backend k3s_servers
          balance roundrobin
          server espresso-0 10.0.186.18:6443 check
          server espresso-1 10.0.186.19:6443 check
          server espresso-2 10.0.186.20:6443 check

        frontend http_ing
          bind *:80
          default_backend http_servers
        backend http_servers
          balance roundrobin
          server espresso-0 10.0.186.18:80 check
          server espresso-1 10.0.186.19:80 check
          server espresso-2 10.0.186.20:80 check

        frontend https_ing
          bind *:443
          default_backend https_servers
        backend https_servers
          balance roundrobin
          server espresso-0 10.0.186.18:443 check
          server espresso-1 10.0.186.19:443 check
          server espresso-2 10.0.186.20:443 check
      '';
    };
  };
}
