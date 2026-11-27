{
  flake.modules.nixos.macchiato =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      baseDomain = "asgard.michaelbrusegard.com";
      routerDomain = "router.${baseDomain}";
      netbirdPublicDomain = "netbird.${baseDomain}";
    in
    {
      # Plain TCP to TLS bridge so the k8s internal gateway can reach the Unifi
      # HTTPS UI published at unifi.${baseDomain}.
      systemd.services.unifi-proxy = {
        after = [
          "network.target"
          "unifi.service"
        ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${lib.getExe pkgs.socat} TCP-LISTEN:8444,fork,reuseaddr OPENSSL:127.0.0.1:8443,verify=0";
          Restart = "always";
        };
      };

      services = {
        cloudflare-dyndns.domains = [
          routerDomain
          "mx.manafishrov.com"
          "mx.${baseDomain}"
          # Personal Stalwart web, JMAP and administration via the HTTPS Gateway.
          "mail.${baseDomain}"
        ];

        # Advertise IPv6 prefixes on both bridges so LAN devices get public
        # GUA addresses (from ISP prefix delegation) via SLAAC
        # The delegated prefix can change on a DHCPv6 renewal; radvd's default
        # lifetimes would keep clients on a dead prefix for up to four hours.
        # Short lifetimes let them move within half an hour (as on cortado).
        radvd = {
          enable = true;
          config = ''
            interface br_clients {
              AdvSendAdvert on;
              prefix ::/64 {
                AdvOnLink on;
                AdvAutonomous on;
                AdvPreferredLifetime 1800;
                AdvValidLifetime 3600;
              };
            };

            interface br_servers {
              AdvSendAdvert on;
              prefix ::/64 {
                AdvOnLink on;
                AdvAutonomous on;
                AdvPreferredLifetime 1800;
                AdvValidLifetime 3600;
              };
            };

            interface iot {
              AdvSendAdvert on;
              prefix ::/64 {
                AdvOnLink on;
                AdvAutonomous on;
                AdvPreferredLifetime 1800;
                AdvValidLifetime 3600;
              };
            };

            interface guest {
              AdvSendAdvert on;
              prefix ::/64 {
                AdvOnLink on;
                AdvAutonomous on;
                AdvPreferredLifetime 1800;
                AdvValidLifetime 3600;
              };
            };
          '';
        };

        # Bind Homebridge to the client VLAN so HomeKit devices can discover it
        avahi.allowInterfaces = [ "br_clients" ];
        # br_clients is trusted, so mDNS needs no port opened on the others.
        avahi.openFirewall = false;
        openssh.openFirewall = lib.mkForce false;
        homebridge.settings.bridge.bind = [ "10.0.186.1" ];

        # DHCP-only server (port = 0 disables DNS; blocky handles DNS instead)
        dnsmasq = {
          enable = true;
          settings = {
            port = 0;
            bind-interfaces = true;
            interface = [
              "br_clients"
              "br_servers"
              "iot"
              "guest"
            ];
            dhcp-authoritative = true;
            dhcp-range = [
              "set:br_clients,10.0.186.2,10.0.186.254,24h"
              "set:br_servers,10.0.187.2,10.0.187.254,24h"
              "set:iot,10.0.189.2,10.0.189.254,24h"
              "set:guest,10.0.190.2,10.0.190.254,1h"
            ];
            dhcp-option = [
              "tag:br_clients,option:router,10.0.186.1"
              "tag:br_clients,option:dns-server,10.0.186.1"
              "tag:br_servers,option:router,10.0.187.1"
              "tag:br_servers,option:dns-server,10.0.187.1"
              "tag:iot,option:router,10.0.189.1"
              "tag:iot,option:dns-server,10.0.189.1"
              "tag:guest,option:router,10.0.190.1"
              "tag:guest,option:dns-server,10.0.190.1"
            ];
            dhcp-host = [
              "1c:0b:8b:ba:87:6c,10.0.186.2,small-living-room-ap"
              "1c:0b:8b:ba:87:54,10.0.186.3,basement-ap"
              "1c:0b:8b:ba:87:81,10.0.186.4,office-ap"

              "d0:d2:b0:9d:70:18,10.0.186.8,small-living-room-tv"
              "d0:d2:b0:96:23:88,10.0.186.9,basement-tv"

              "f0:2f:74:15:dd:d1,10.0.186.16,ristretto"

              "dc:a6:32:8d:5f:44,10.0.186.17,freddo"
              "dc:a6:32:64:dc:91,10.0.186.18,manata"

              "c8:98:db:19:12:30,10.0.187.2,espresso-0"
              "b4:96:91:26:31:fa,10.0.187.3,espresso-1"
              "b4:96:91:ff:ff:ff,10.0.187.4,espresso-2"

              "e8:06:90:aa:3f:5c,10.0.189.21,cubeman"
            ];
          };
        };

        # BGP peering with the k3s cluster (Cilium) for internal service VIPs and
        # pod CIDRs. The router needs pod return routes because cluster DNS and
        # some LAN-facing services see native pod source addresses.
        frr = {
          bgpd.enable = true;
          config = ''
            ip prefix-list PL-CILIUM-VIPS-V4 seq 10 permit 10.0.188.0/24 le 32
            ip prefix-list PL-CILIUM-VIPS-V4 seq 20 permit 10.42.0.0/16 le 24
            ipv6 prefix-list PL-CILIUM-VIPS-V6 seq 10 permit fd7a:115c:a1e0:188::/64 le 128
            ipv6 prefix-list PL-CILIUM-VIPS-V6 seq 20 permit fd42::/56 le 64

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

        blocky.settings = {
          # Forward both zones to k8s-gateway so LAN clients reach cluster
          # services via the internal LB VIP instead of bouncing off the WAN
          # IP. Non-cluster manafishrov.com subdomains fall through to upstream
          # DNS via k8s-gateway's fallthrough config.
          conditional.mapping = {
            "${baseDomain}" = "10.0.188.5,fd7a:115c:a1e0:188::5";
            "manafishrov.com" = "10.0.188.5,fd7a:115c:a1e0:188::5";
            "eldians.com" = "10.0.188.5,fd7a:115c:a1e0:188::5";
          };
          customDNS.mapping = {
            "${routerDomain}" = "10.0.186.1,fd7a:115c:a1e0:186::1";
            # SMTP uses the shared edge; mail.* web names resolve through k8s-gateway.
            "mx.manafishrov.com" = "10.0.188.12,fd7a:115c:a1e0:188::12";
            "mx.${baseDomain}" = "10.0.188.12,fd7a:115c:a1e0:188::12";
            # The personal MTA-STS names sit outside the k8s-gateway zones and
            # would resolve to the WAN IP, which does not hairpin. Point them
            # at the internal gateway so LAN clients and Uptime Kuma reach them.
            "mta-sts.michaelbrusegard.com" = "10.0.188.3,fd7a:115c:a1e0:188::3";
            "mta-sts.michbrus.com" = "10.0.188.3,fd7a:115c:a1e0:188::3";
          };
        };

        netbird = {
          useRoutingFeatures = "server";
          clients.default = {
            interface = "vpn_clients";
            port = 51820;
            config = {
              DNSLabels = [ config.networking.hostName ];
              ManagementURL = {
                Scheme = "https";
                Host = "${netbirdPublicDomain}:443";
              };
            };
            login = {
              enable = true;
              inherit (config.secrets.netbird) setupKeyFile;
            };
          };
        };
      };
    };
}
