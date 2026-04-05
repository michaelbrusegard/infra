_: let
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
      denyInterfaces = ["br_clients" "br_servers"];
      extraConfig = ''
        interface ${wanInterface}
          ia_na 1
          ia_pd 1 br_clients/0/64 br_servers/1/64
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
        # "wg0"
      ];
    };

    firewall = {
      enable = true;
      # All traffic from LAN bridges is trusted (no per-port filtering)
      trustedInterfaces = ["br_clients" "br_servers"];

      extraForwardRules = ''
        # IPv6 forwarding protection: devices on the LAN get public IPv6 addresses
        # via prefix delegation, so without these rules they would be directly
        # reachable from the internet. Allow return traffic, block everything else.
        iifname "${wanInterface}" ct state established,related accept
        iifname "${wanInterface}" drop

        # Internal service VIP subnet: published cluster services live on 188,
        # so clients and servers are both allowed to reach those routed VIPs.
        iifname { "br_clients", "br_servers" } ip daddr 10.0.188.0/24 accept
        iifname { "br_clients", "br_servers" } ip6 daddr fd7a:115c:a1e0:188::/64 accept

        # Allow servers to initiate connections to client devices when needed.
        iifname "br_servers" oifname "br_clients" accept
      '';

      # Ports open to the internet on the WAN interface
      # SSH (port 2286) is opened separately by openssh module's openFirewall = true
      interfaces = {
        # "wg0" = {
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
      '';
    };

    # mDNS reflector so devices on different bridges can discover each other
    avahi = {
      enable = true;
      reflector = true;
      allowInterfaces = ["br_clients" "br_servers"];
      publish.enable = true;
      publish.userServices = true;
      openFirewall = true;
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
        ];
        dhcp-authoritative = true;
        dhcp-range = [
          "set:br_clients,10.0.186.2,10.0.186.254,24h"
          "set:br_servers,10.0.187.2,10.0.187.254,24h"
        ];
        dhcp-option = [
          "tag:br_clients,option:router,10.0.186.1"
          "tag:br_clients,option:dns-server,10.0.186.1"
          "tag:br_servers,option:router,10.0.187.1"
          "tag:br_servers,option:dns-server,10.0.187.1"
        ];
        dhcp-host = [
          "90:72:40:04:E7:73,10.0.186.2,entrance-ap"
          "6c:70:9f:ec:10:23,10.0.186.3,basement-ap"
          "6c:70:9f:ec:04:3f,10.0.186.4,office-ap"
          "24:a0:74:73:05:48,10.0.186.5,workshop-ap"
          "d0:d2:b0:9d:70:18,10.0.186.6,small-living-room-tv"
          "d0:d2:b0:96:23:88,10.0.186.8,basement-tv"

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
  };
}
