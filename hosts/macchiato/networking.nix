{config, ...}: let
  wanInterface = "enp1s0";
  clientInterfaces = ["enp2s0" "sfp0"];
  serverInterfaces = ["enp3s0"];
in {
  boot.kernel.sysctl = {
    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv6.conf.${wanInterface}.accept_ra" = 2;
  };

  networking = {
    useDHCP = false;
    bridges.br_clients.interfaces = clientInterfaces;
    bridges.br_servers.interfaces = serverInterfaces;

    interfaces = {
      "${wanInterface}".useDHCP = true;
      br_clients = {
        useDHCP = false;
        ipv4.addresses = [
          {
            address = "10.0.186.1";
            prefixLength = 24;
          }
        ];
      };
      br_servers = {
        useDHCP = false;
        ipv4.addresses = [
          {
            address = "10.0.187.1";
            prefixLength = 24;
          }
        ];
      };
    };

    dhcpcd = {
      enable = true;
      denyInterfaces = ["br_clients" "br_servers"];
      extraConfig = ''
        interface ${wanInterface}
          ia_na 1
          ia_pd 1 br_clients/0/64 br_servers/1/64
      '';
    };

    nat = {
      enable = true;
      externalInterface = wanInterface;
      internalInterfaces = [
        "br_clients"
        "br_servers"
        /*
        "wg0"
        */
      ];
    };

    firewall = {
      enable = true;
      trustedInterfaces = ["br_clients" "br_servers"];

      # Control traffic between internal subnets
      extraForwardRules = ''
        # Allow servers to reach out to clients (e.g., Home Assistant polling smart plugs)
        iifname "br_servers" oifname "br_clients" accept

        # Restrict clients to only SSH, HTTP, and HTTPS on the servers directly
        iifname "br_clients" oifname "br_servers" tcp dport { 22, 80, 443 } accept
      '';

      interfaces = {
        # wg0 = {
        #   allowedTCPPorts = [53 9090 3000 1883 8080 8581 6443];
        #   allowedUDPPorts = [53];
        # };

        "${wanInterface}" = {
          allowedTCPPorts = [80 443];
          # allowedUDPPorts = [51820];
        };
      };
    };

    # wireguard.interfaces.wg0 = {
    #   ips = ["10.0.187.1/24"];
    #   listenPort = 51820;
    #   inherit (config.secrets.wireguard) privateKeyFile;
    #   inherit (config.secrets.wireguard) peers;
    # };
  };

  services = {
    radvd = {
      enable = true;
      config = ''
        interface br_clients {
          AdvSendAdvert on;
          prefix ::/64 {
            AdvOnLink on;
            AdvAutonomous on;
          };
        };

        interface br_servers {
          AdvSendAdvert on;
          prefix ::/64 {
            AdvOnLink on;
            AdvAutonomous on;
          };
        };
      '';
    };

    avahi = {
      enable = true;
      reflector = true;
      allowInterfaces = ["br_clients" "br_servers"];
      openFirewall = true;
    };

    dnsmasq = {
      enable = true;
      settings = {
        port = 0;
        dhcp-range = [
          "interface:br_clients,10.0.186.2,10.0.186.254,24h"
          "interface:br_servers,10.0.187.2,10.0.187.254,24h"
        ];
        dhcp-option = [
          "tag:br_clients,option:router,10.0.186.1"
          "tag:br_clients,option:dns-server,10.0.186.1"
          "tag:br_servers,option:router,10.0.187.1"
          "tag:br_servers,option:dns-server,10.0.187.1"
        ];
        dhcp-host = [
          "00:00:00:00:00:01,10.0.186.2,entrance-ap"
          "6c:70:9f:ec:10:23,10.0.186.3,basement-ap"
          "6c:70:9f:ec:04:3f,10.0.186.4,office-ap"
          "24:a0:74:73:05:48,10.0.186.5,workshop-ap"
          "d0:d2:b0:9d:70:18,10.0.186.6,small-living-room-tv"
          "d0:d2:b0:96:23:88,10.0.186.8,basement-tv"

          "c8:98:db:19:12:30,10.0.187.2,espresso-0"
          "24:4b:fe:cc:18:0e,10.0.187.3,espresso-1"
          "24:4b:fe:ca:8d:9b,10.0.187.4,espresso-2"

          "e8:06:90:aa:3f:5c,10.0.186.21,cubeman"
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
          server espresso-0 10.0.187.2:6443 check
          server espresso-1 10.0.187.3:6443 check
          server espresso-2 10.0.187.4:6443 check

        frontend http_ing
          bind *:80
          default_backend http_servers
        backend http_servers
          balance roundrobin
          server espresso-0 10.0.187.2:80 check
          server espresso-1 10.0.187.3:80 check
          server espresso-2 10.0.187.4:80 check

        frontend https_ing
          bind *:443
          default_backend https_servers
        backend https_servers
          balance roundrobin
          server espresso-0 10.0.187.2:443 check
          server espresso-1 10.0.187.3:443 check
          server espresso-2 10.0.187.4:443 check
      '';
    };
  };
}
