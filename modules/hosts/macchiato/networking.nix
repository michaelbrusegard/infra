{
  flake.modules.nixos.macchiato =
    {
      config,
      lib,
      ...
    }:
    let
      wanInterface = "enp2s0";
      clientInterfaces = [
        "enp3s0"
        "enp4s0"
      ];
      serverInterfaces = [
        "enp5s0"
        "enp1s0f0"
        "enp1s0f1"
      ];

      publicGateway = {
        ipv4 = "10.0.188.2";
        ipv6 = "fd7a:115c:a1e0:188::2";
      };
      stalwartEdge = {
        ipv4 = "10.0.188.12";
        ipv6 = "fd7a:115c:a1e0:188::12";
      };
      netbirdCoturn = {
        ipv4 = "10.0.188.34";
        ipv6 = "fd7a:115c:a1e0:188::34";
      };
      minecraftRouter = {
        ipv4 = "10.0.188.50";
        ipv6 = "fd7a:115c:a1e0:188::50";
      };
      nextcloudEturnal = {
        ipv4 = "10.0.187.3";
        ipv6 = "fd7a:115c:a1e0:187::3";
      };
      forward =
        destination: proto: port:
        destination // { inherit proto port; };

      # Public WAN forwards are declared once and rendered for both address
      # families. Keep port ranges separate because nftables cannot represent a
      # range-to-range translation in the anonymous map used for single ports.
      publicPortForwards = [
        (forward publicGateway "tcp" 80)
        (forward publicGateway "tcp" 443)
        # Shared server-to-server SMTP edge. Clients use JMAP through HTTPS.
        (forward stalwartEdge "tcp" 25)
        # Backup MX handoff requires the pinned cortado client certificate.
        (forward stalwartEdge "tcp" 2525)
        (forward netbirdCoturn "udp" 3478)
        # mc-router fans out by handshake hostname (*.eldians.com).
        (forward minecraftRouter "tcp" 25565)
        (forward nextcloudEturnal "udp" 5349)
        (forward nextcloudEturnal "tcp" 5349)
      ];
      turnRelayForward = nextcloudEturnal // {
        proto = "udp";
        ports = "49152-65535";
      };
      mkIPv4Forward = forward: {
        destination = "${forward.ipv4}:${toString forward.port}";
        inherit (forward) proto;
        sourcePort = forward.port;
      };
      mkIPv6Forward =
        forward: "${forward.proto} . ${toString forward.port} : ${forward.ipv6} . ${toString forward.port}";
    in
    {
      boot.kernel.sysctl = {
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

        nameservers = [
          "127.0.0.1"
          "::1"
          "1.1.1.1"
          "2606:4700:4700::1111"
        ];

        vlans = {
          iot = {
            id = 189;
            interface = "br_clients";
          };
          guest = {
            id = 190;
            interface = "br_clients";
          };
        };

        interfaces = {
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

          # IoT VLAN: isolated smart-home devices with internet access (10.0.189.0/24)
          iot = {
            useDHCP = false;
            ipv4.addresses = [
              {
                address = "10.0.189.1";
                prefixLength = 24;
              }
            ];
            ipv6.addresses = [
              {
                address = "fd7a:115c:a1e0:189::1";
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
          denyInterfaces = [
            "br_clients"
            "br_servers"
            "iot"
            "guest"
          ];
          extraConfig = ''
            interface ${wanInterface}
              ia_na 1
              ia_pd 1 br_clients/0/64 br_servers/1/64 iot/2/64 guest/3/64
          '';
        };

        # IPv4 NAT (masquerade) for outbound internet access from both VLANs.
        # Outbound IPv6 stays native — devices use public GUA addresses from prefix
        # delegation. Inbound IPv6 DNAT is defined separately below because the
        # cluster service VIPs use stable ULAs.
        nat = {
          enable = true;
          externalInterface = wanInterface;
          internalInterfaces = [
            "br_clients"
            "br_servers"
            "iot"
            "guest"
            "vpn_clients"
          ];
          forwardPorts = map mkIPv4Forward publicPortForwards;
        };

        # networking.nat renders ranges as anonymous range-to-range maps, which
        # nftables does not support. Address-only DNAT preserves the relay port.
        nftables.tables."ipv4-relay-port-forward" = {
          family = "ip";
          content = ''
            chain prerouting {
              type nat hook prerouting priority dstnat; policy accept;

              iifname "${wanInterface}" ${turnRelayForward.proto} dport ${turnRelayForward.ports} dnat to ${turnRelayForward.ipv4}
            }
          '';
        };

        # Mirror the IPv4 WAN forwards above for IPv6. The public DNS records point
        # at macchiato's dynamic WAN GUA, while the routed cluster service VIPs use
        # stable ULAs, so inbound connections need destination NAT. Keeping this in
        # a dedicated table avoids enabling outbound NAT66 for the LAN bridges.
        nftables.tables."ipv6-port-forward" = {
          family = "ip6";
          content = ''
            chain prerouting {
              type nat hook prerouting priority dstnat; policy accept;

              iifname "${wanInterface}" meta l4proto { tcp, udp } dnat meta l4proto . th dport map { ${
                lib.concatMapStringsSep ", " mkIPv6Forward publicPortForwards
              } }

              # Address-only DNAT preserves the original relay port. nftables does
              # not support mapping one anonymous port range to another.
              iifname "${wanInterface}" ${turnRelayForward.proto} dport ${turnRelayForward.ports} dnat to ${turnRelayForward.ipv6}
            }
          '';
        };

        firewall = {
          enable = true;
          trustedInterfaces = [
            "br_clients"
            "br_servers"
            "vpn_clients"
          ];
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
            iifname "vpn_clients" ip daddr { 10.0.186.0/24, 10.0.187.0/24, 10.0.188.0/24, 10.0.189.0/24 } accept
            iifname "vpn_clients" ip6 daddr { fd7a:115c:a1e0:186::/64, fd7a:115c:a1e0:187::/64, fd7a:115c:a1e0:188::/64, fd7a:115c:a1e0:189::/64 } accept

            # NetBird exit-node: VPN clients that activate the 0.0.0.0/0 route
            # have their internet traffic forwarded out via WAN (NAT masquerade).
            iifname "vpn_clients" oifname "${wanInterface}" accept

            # Stated here so client internet access does not hinge on the accept
            # rule the NAT module adds for its internal interfaces.
            iifname "br_clients" oifname "${wanInterface}" accept

            # Allow servers to initiate connections to client devices when needed.
            iifname "br_servers" oifname "br_clients" accept

            # Allow servers, including k3s nodes and pods, to reach the internet.
            iifname "br_servers" oifname "${wanInterface}" accept

            # Allow client devices to reach servers (e.g. SSH to cluster nodes).
            iifname "br_clients" oifname "br_servers" accept

            # Allow client devices to reach IoT devices.
            iifname "br_clients" oifname "iot" accept

            # IoT network: internet only, resolving through this router. Outside
            # DNS is dropped so a device cannot bypass blocky with its own resolver.
            iifname "iot" oifname "${wanInterface}" meta l4proto { tcp, udp } th dport { 53, 853 } drop
            iifname "iot" oifname "${wanInterface}" accept
            # Internal subnets are blocked by the default-drop policy.

            # Guest network: internet only, no access to internal subnets.
            # Internal traffic is blocked by the default-drop policy.
            iifname "guest" oifname "${wanInterface}" accept
          '';

          # SSH stays reachable from the WAN. The trusted interfaces reach it
          # anyway, and guest and IoT get DHCP and DNS only.
          interfaces = {
            ${wanInterface}.allowedTCPPorts = config.services.openssh.ports;
            # IoT devices need DHCP and DNS from the router, nothing else
            "iot" = {
              allowedTCPPorts = [ 53 ];
              allowedUDPPorts = [
                53
                67
              ];
            };
            # Guest devices need DHCP and DNS from the router, nothing else
            "guest" = {
              allowedTCPPorts = [ 53 ];
              allowedUDPPorts = [
                53
                67
              ];
            };
          };
        };
      };

    };
}
