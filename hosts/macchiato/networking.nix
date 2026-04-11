{config, ...}: let
  wanInterface = "enp2s0";
  clientInterfaces = ["enp3s0" "enp4s0"];
  serverInterfaces = ["enp5s0" "enp1s0f0" "enp1s0f1"];
in {
  boot.kernel.sysctl = {
    # Required for routing traffic between bridges and to the internet
    "net.ipv6.conf.all.forwarding" = 1;
    # Accept router advertisements on WAN even with forwarding enabled
    # (normally forwarding disables RA acceptance; value 2 overrides that)
    "net.ipv6.conf.${wanInterface}.accept_ra" = 2;
  };

  networking = {
    useDHCP = false;
    nftables.enable = true;
    bridges.br_clients.interfaces = clientInterfaces;
    bridges.br_servers.interfaces = serverInterfaces;

    vlans.guest = {
      id = 190;
      interface = "br_clients";
    };

    interfaces = {
      # WAN gets its address from the ISP via DHCP
      "${wanInterface}".useDHCP = true;

      # Client VLAN: personal devices, APs, TVs (10.0.186.0/24)
      br_clients = {
        useDHCP = false;
        ipv4.addresses = [
          {
            address = "10.0.186.1";
            prefixLength = 24;
          }
        ];
        # Stable ULA gateway for internal IPv6 (not affected by ISP prefix changes)
        ipv6.addresses = [
          {
            address = "fd7a:115c:a1e0:186::1";
            prefixLength = 64;
          }
        ];
      };

      # Guest VLAN: isolated internet-only access for visitors (10.0.190.0/24)
      guest = {
        useDHCP = false;
        ipv4.addresses = [
          {
            address = "10.0.190.1";
            prefixLength = 24;
          }
        ];
        ipv6.addresses = [
          {
            address = "fd7a:115c:a1e0:190::1";
            prefixLength = 64;
          }
        ];
      };

      # Server VLAN: k3s cluster nodes and other servers (10.0.187.0/24)
      br_servers = {
        useDHCP = false;
        ipv4.addresses = [
          {
            address = "10.0.187.1";
            prefixLength = 24;
          }
        ];
        ipv6.addresses = [
          {
            address = "fd7a:115c:a1e0:187::1";
            prefixLength = 64;
          }
        ];
      };
    };

    # WAN DHCP client: requests an IPv4 address (ia_na) and an IPv6 prefix
    # delegation (ia_pd) from the ISP, splitting the delegated /64s across bridges
    dhcpcd = {
      enable = true;
      denyInterfaces = ["br_clients" "br_servers" "guest"];
      extraConfig = ''
        interface ${wanInterface}
          ia_na 1
          ia_pd 1 br_clients/0/64 br_servers/1/64 guest/2/64
      '';
    };

    # IPv4 NAT (masquerade) for outbound internet access from both VLANs
    # IPv6 does not need NAT — devices use public GUA addresses from prefix delegation
    nat = {
      enable = true;
      externalInterface = wanInterface;
      internalInterfaces = [
        "br_clients"
        "br_servers"
        "guest"
      ];
      forwardPorts = [
        {
          destination = "10.0.188.34:3478";
          proto = "udp";
          sourcePort = 3478;
        }
      ];
    };

    firewall = {
      enable = true;
      # All traffic from LAN bridges is trusted (no per-port filtering)
      trustedInterfaces = ["br_clients" "br_servers" "vpn_clients"];
      # Create a forward chain with default-drop policy so extraForwardRules
      # are actually enforced. Established/related and NAT-forwarded traffic
      # are handled automatically by the NixOS firewall module.
      filterForward = true;

      extraForwardRules = ''
        # Block unsolicited new connections from the internet. LAN devices get
        # public IPv6 addresses via prefix delegation, so this is essential.
        iifname "${wanInterface}" drop

        # Internal service VIP subnet: published cluster services live on 188,
        # so clients and servers are both allowed to reach those routed VIPs.
        iifname { "br_clients", "br_servers" } ip daddr 10.0.188.0/24 accept
        iifname { "br_clients", "br_servers" } ip6 daddr fd7a:115c:a1e0:188::/64 accept

        # NetBird peers may reach the internal client, server, and cluster VIP
        # subnets through macchiato.
        iifname "vpn_clients" ip daddr { 10.0.186.0/24, 10.0.187.0/24, 10.0.188.0/24 } accept
        iifname "vpn_clients" ip6 daddr { fd7a:115c:a1e0:186::/64, fd7a:115c:a1e0:187::/64, fd7a:115c:a1e0:188::/64 } accept

        # Allow servers to initiate connections to client devices when needed.
        iifname "br_servers" oifname "br_clients" accept

        # Guest network: internet only, no access to internal subnets.
        # Internal traffic is blocked by the default-drop policy.
        iifname "guest" oifname "${wanInterface}" accept
      '';

      # Ports open to the internet on the WAN interface
      # SSH (port 2286) is opened separately by openssh module's openFirewall = true
      interfaces = {
        "${wanInterface}" = {
          allowedTCPPorts = [80 443];
          allowedUDPPorts = [3478];
        };
        # Guest devices need DHCP and DNS from the router, nothing else
        "guest" = {
          allowedTCPPorts = [53];
          allowedUDPPorts = [53 67];
        };
      };
    };
  };

  services = {
    # Advertise IPv6 prefixes on both bridges so LAN devices get public
    # GUA addresses (from ISP prefix delegation) via SLAAC
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

        interface guest {
          AdvSendAdvert on;
          prefix ::/64 {
            AdvOnLink on;
            AdvAutonomous on;
          };
        };
      '';
    };

    # Reverse proxy for local services so they are reachable on port 80 via
    # their .home.arpa DNS names. Only listens on the client VLAN.
    caddy = {
      enable = true;
      virtualHosts =
        {
          "http://homebridge.home.arpa" = {
            listenAddresses = ["10.0.186.1" "fd7a:115c:a1e0:186::1"];
            extraConfig = "reverse_proxy 127.0.0.1:8581";
          };
          "http://zigbee.home.arpa" = {
            listenAddresses = ["10.0.186.1" "fd7a:115c:a1e0:186::1"];
            extraConfig = "reverse_proxy 127.0.0.1:8082";
          };
        }
        // {
          "https://${config.secrets.pocket-id.publicDomain}" = {
            extraConfig = "reverse_proxy http://10.0.188.3:80";
          };
        }
        // {
          "https://${config.secrets.uptime-kuma.publicDomain}" = {
            extraConfig = ''
              @status path /status /status/*
              @status-api path /api/status-page/*
              @assets path /assets/*
              @upload path /upload/*
              @icon path /icon.svg /favicon.ico

              handle @status {
                reverse_proxy http://10.0.188.4:80 {
                  header_up Host uptime.home.arpa
                }
              }
              handle @status-api {
                reverse_proxy http://10.0.188.4:80 {
                  header_up Host uptime.home.arpa
                }
              }
              handle @assets {
                reverse_proxy http://10.0.188.4:80 {
                  header_up Host uptime.home.arpa
                }
              }
              handle @upload {
                reverse_proxy http://10.0.188.4:80 {
                  header_up Host uptime.home.arpa
                }
              }
              handle @icon {
                reverse_proxy http://10.0.188.4:80 {
                  header_up Host uptime.home.arpa
                }
              }
              handle {
                respond 404
              }
            '';
          };
        }
        // {
          "https://${config.secrets.netbird.publicDomain}" = {
            extraConfig = ''
              @signal_grpc path /signalexchange.SignalExchange/*
              handle @signal_grpc {
                reverse_proxy h2c://10.0.188.32:10000
              }

              @mgmt_grpc path /management.ManagementService/* /management.ProxyService/*
              handle @mgmt_grpc {
                reverse_proxy h2c://10.0.188.30:80
              }

              @relay path /relay /relay/* /ws-proxy /ws-proxy/*
              handle @relay {
                reverse_proxy http://10.0.188.33:33080
              }

              @api path /api /api/*
              handle @api {
                reverse_proxy http://10.0.188.30:80
              }

              handle {
                reverse_proxy http://10.0.188.31:80
              }
            '';
          };
        };
    };

    # Bind Homebridge to the client VLAN so HomeKit devices can discover it
    homebridge.settings.bridge.bind = ["10.0.186.1"];

    # DHCP-only server (port = 0 disables DNS; blocky handles DNS instead)
    dnsmasq = {
      enable = true;
      settings = {
        port = 0;
        bind-interfaces = true;
        interface = [
          "br_clients"
          "br_servers"
          "guest"
        ];
        dhcp-authoritative = true;
        dhcp-range = [
          "set:br_clients,10.0.186.2,10.0.186.254,24h"
          "set:br_servers,10.0.187.2,10.0.187.254,24h"
          "set:guest,10.0.190.2,10.0.190.254,1h"
        ];
        dhcp-option = [
          "tag:br_clients,option:router,10.0.186.1"
          "tag:br_clients,option:dns-server,10.0.186.1"
          "tag:br_servers,option:router,10.0.187.1"
          "tag:br_servers,option:dns-server,10.0.187.1"
          "tag:guest,option:router,10.0.190.1"
          "tag:guest,option:dns-server,10.0.190.1"
        ];
        dhcp-host = [
          "1c:0b:8b:ba:87:6c,10.0.186.2,small-living-room-ap"
          "1c:0b:8b:ba:87:54,10.0.186.3,basement-ap"
          "1c:0b:8b:ba:87:81,10.0.186.4,office-ap"

          "d0:d2:b0:9d:70:18,10.0.186.8,small-living-room-tv"
          "d0:d2:b0:96:23:88,10.0.186.9,basement-tv"

          "c8:98:db:19:12:30,10.0.187.2,espresso-0"
          "b4:96:91:26:31:fa,10.0.187.3,espresso-1"
          "b4:96:91:ff:ff:ff,10.0.187.4,espresso-2"

          "e8:06:90:aa:3f:5c,10.0.186.21,cubeman"
        ];
      };
    };

    # BGP peering with the k3s cluster (Cilium) for internal service VIPs.
    # Both IPv4 and IPv6 VIPs are learned dynamically over BGP with ECMP.
    frr = {
      bgpd.enable = true;
      config = ''
        ip prefix-list PL-CILIUM-VIPS-V4 seq 10 permit 10.0.188.0/24 le 32
        ipv6 prefix-list PL-CILIUM-VIPS-V6 seq 10 permit fd7a:115c:a1e0:188::/64 le 128

        route-map RM-CILIUM-IN-V4 permit 10
          match ip address prefix-list PL-CILIUM-VIPS-V4

        route-map RM-CILIUM-IN-V6 permit 10
          match ipv6 address prefix-list PL-CILIUM-VIPS-V6

        route-map RM-CILIUM-OUT deny 10

        router bgp 65000
          bgp router-id 10.0.187.1
          no bgp default ipv4-unicast

          # Peer with each k3s node over both IPv4 and IPv6.
          neighbor 10.0.187.2 remote-as 65001
          neighbor 10.0.187.3 remote-as 65001
          neighbor 10.0.187.4 remote-as 65001
          neighbor fd7a:115c:a1e0:187::2 remote-as 65001
          neighbor fd7a:115c:a1e0:187::3 remote-as 65001
          neighbor fd7a:115c:a1e0:187::4 remote-as 65001

          address-family ipv4 unicast
            # ECMP: distribute traffic across all 3 nodes
            maximum-paths 3
            neighbor 10.0.187.2 activate
            neighbor 10.0.187.3 activate
            neighbor 10.0.187.4 activate
            neighbor 10.0.187.2 route-map RM-CILIUM-IN-V4 in
            neighbor 10.0.187.3 route-map RM-CILIUM-IN-V4 in
            neighbor 10.0.187.4 route-map RM-CILIUM-IN-V4 in
            neighbor 10.0.187.2 route-map RM-CILIUM-OUT out
            neighbor 10.0.187.3 route-map RM-CILIUM-OUT out
            neighbor 10.0.187.4 route-map RM-CILIUM-OUT out
          exit-address-family

          address-family ipv6 unicast
            maximum-paths 3
            neighbor fd7a:115c:a1e0:187::2 activate
            neighbor fd7a:115c:a1e0:187::3 activate
            neighbor fd7a:115c:a1e0:187::4 activate
            neighbor fd7a:115c:a1e0:187::2 route-map RM-CILIUM-IN-V6 in
            neighbor fd7a:115c:a1e0:187::3 route-map RM-CILIUM-IN-V6 in
            neighbor fd7a:115c:a1e0:187::4 route-map RM-CILIUM-IN-V6 in
            neighbor fd7a:115c:a1e0:187::2 route-map RM-CILIUM-OUT out
            neighbor fd7a:115c:a1e0:187::3 route-map RM-CILIUM-OUT out
            neighbor fd7a:115c:a1e0:187::4 route-map RM-CILIUM-OUT out
          exit-address-family
      '';
    };

    blocky.settings.customDNS = {
      mapping =
        {
          "homebridge.home.arpa" = "10.0.186.1,fd7a:115c:a1e0:186::1";
          "zigbee.home.arpa" = "10.0.186.1,fd7a:115c:a1e0:186::1";
          "hubble.home.arpa" = "10.0.188.2,fd7a:115c:a1e0:188::2";
          "uptime.home.arpa" = "10.0.188.4,fd7a:115c:a1e0:188::4";
        }
        // {
          "${config.secrets.pocket-id.publicDomain}" = "10.0.186.1,fd7a:115c:a1e0:186::1";
          "${config.secrets.netbird.publicDomain}" = "10.0.186.1,fd7a:115c:a1e0:186::1";
          "${config.secrets.uptime-kuma.publicDomain}" = "10.0.186.1,fd7a:115c:a1e0:186::1";
        };
    };

    netbird = {
      useRoutingFeatures = "server";
      clients.default.interface = "vpn_clients";
    };
  };
}
