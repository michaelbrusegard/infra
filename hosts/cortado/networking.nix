{
  config,
  lib,
  ...
}: let
  # Physical labels verified on the Qotom chassis:
  #   ports 1-2: 10 GbE (Aquantia AQC113C)
  #   ports 3-6: 2.5 GbE (Intel I226-V)
  wanInterface = "enp7s0"; # port 6
  lanInterfaces = [
    "enp1s0" # port 1
    "enp2s0" # port 2
    "enp4s0" # port 3, planned UniFi AP trunk
    "enp5s0" # port 4
    "enp6s0" # port 5
  ];
  lanBridge = "br_lan";
  iotInterface = "iot";
  netbirdInterface = "vpn_clients";
  baseDomain = "midgard.michaelbrusegard.com";
  routerDomain = "router.${baseDomain}";
in {
  boot.kernel.sysctl = {
    "net.ipv6.conf.all.forwarding" = 1;
    # Forwarding normally disables WAN router advertisements. Value 2 keeps
    # them enabled so dhcpcd can obtain a native address and delegated prefix.
    "net.ipv6.conf.${wanInterface}.accept_ra" = 2;
  };

  networking = {
    useDHCP = false;
    nftables.enable = true;
    bridges.${lanBridge}.interfaces = lanInterfaces;

    nameservers = [
      "127.0.0.1"
      "::1"
      "1.1.1.1"
      "2606:4700:4700::1111"
    ];

    vlans.${iotInterface} = {
      id = 17;
      interface = lanBridge;
    };

    interfaces = {
      "${wanInterface}".useDHCP = true;
      "${lanBridge}" = {
        useDHCP = false;
        ipv4.addresses = [
          {
            address = "10.0.15.1";
            prefixLength = 24;
          }
        ];
        ipv6.addresses = [
          {
            address = "fd7a:115c:a1e0:15::1";
            prefixLength = 64;
          }
        ];
      };
      "${iotInterface}" = {
        useDHCP = false;
        ipv4.addresses = [
          {
            address = "10.0.17.1";
            prefixLength = 24;
          }
        ];
        ipv6.addresses = [
          {
            address = "fd7a:115c:a1e0:17::1";
            prefixLength = 64;
          }
        ];
      };
    };

    # Request native IPv6 and split a delegated prefix between trusted and IoT
    # networks. If the ISP does not delegate a prefix, IPv4 remains unaffected.
    dhcpcd = {
      enable = true;
      denyInterfaces = [lanBridge iotInterface];
      extraConfig = ''
        interface ${wanInterface}
          ia_na 1
          ia_pd 1 ${lanBridge}/0/64 ${iotInterface}/1/64
      '';
    };

    # IPv4 only. Native IPv6 is routed without NAT66.
    nat = {
      enable = true;
      externalInterface = wanInterface;
      internalInterfaces = [
        lanBridge
        iotInterface
        netbirdInterface
      ];
    };

    firewall = {
      enable = true;
      # NetBird peers are gated by the account's access policies, so the host
      # firewall does not filter them again.
      trustedInterfaces = [lanBridge netbirdInterface];
      filterForward = true;

      extraForwardRules = ''
        # Never permit unsolicited forwarding from the ISP.
        iifname "${wanInterface}" drop

        # Trusted clients and NetBird administrators may initiate connections
        # into less-trusted networks. Stateful firewall rules permit replies.
        iifname "${lanBridge}" oifname "${wanInterface}" accept
        iifname "${lanBridge}" oifname "${iotInterface}" accept
        iifname "${netbirdInterface}" oifname { "${lanBridge}", "${iotInterface}", "${wanInterface}" } accept

        # IoT clients cannot initiate connections to trusted clients. Their
        # internet access is limited to web traffic, QUIC, NTP, and essential
        # ICMPv6. DNS must use Cortado rather than an external resolver.
        iifname "${iotInterface}" oifname "${wanInterface}" tcp dport { 80, 443 } accept
        iifname "${iotInterface}" oifname "${wanInterface}" udp dport { 123, 443 } accept
        iifname "${iotInterface}" oifname "${wanInterface}" meta l4proto ipv6-icmp accept
      '';

      interfaces = {
        "${iotInterface}" = {
          allowedTCPPorts = [53];
          allowedUDPPorts = [53 67];
        };
      };
    };
  };

  # Trusted LAN access is covered by trustedInterfaces. Do not expose SSH on
  # the ISP-facing interface.
  services.openssh.openFirewall = lib.mkForce false;

  services = {
    cloudflare-dyndns.domains = [routerDomain];

    # Advertise the delegated prefix so LAN devices get public GUA addresses
    # via SLAAC. The ULAs stay router-side stable service addresses.
    radvd = {
      enable = true;
      config = ''
        interface ${lanBridge} {
          AdvSendAdvert on;
          prefix ::/64 {
            AdvOnLink on;
            AdvAutonomous on;
          };
        };

        interface ${iotInterface} {
          AdvSendAdvert on;
          prefix ::/64 {
            AdvOnLink on;
            AdvAutonomous on;
          };
        };
      '';
    };

    # Blocky owns DNS; dnsmasq only provides DHCP leases and options.
    dnsmasq = {
      enable = true;
      settings = {
        port = 0;
        bind-interfaces = true;
        interface = [lanBridge iotInterface];
        dhcp-authoritative = true;
        dhcp-range = [
          "set:trusted,10.0.15.20,10.0.15.254,24h"
          "set:iot,10.0.17.20,10.0.17.254,24h"
        ];
        dhcp-host = [
          "74:fa:29:26:eb:42,10.0.15.2,unifi-ap"
          "30:23:03:06:6c:3c,10.0.15.10,forte"
        ];
        dhcp-option = [
          "tag:trusted,option:router,10.0.15.1"
          "tag:trusted,option:dns-server,10.0.15.1"
          "tag:iot,option:router,10.0.17.1"
          "tag:iot,option:dns-server,10.0.17.1"
        ];
      };
    };

    blocky.settings = {
      # Unlike macchiato, cortado runs systemd-resolved for NetBird split DNS,
      # which already holds 127.0.0.53:53. Enumerate the listeners rather than
      # binding the wildcard so the two do not collide. Loopback is required
      # because networking.nameservers points the router at its own Blocky.
      ports.dns = [
        "127.0.0.1:53"
        "[::1]:53"
        "10.0.15.1:53"
        "10.0.17.1:53"
      ];
      # Override the public dyndns record on the LAN so local clients reach
      # Cortado directly instead of hairpinning off the WAN address.
      customDNS.mapping = {
        "${routerDomain}" = "10.0.15.1,fd7a:115c:a1e0:15::1";
        "home-assistant.${baseDomain}" = "10.0.15.1,fd7a:115c:a1e0:15::1";
        "unifi.${baseDomain}" = "10.0.15.1,fd7a:115c:a1e0:15::1";
      };
    };

    netbird = {
      useRoutingFeatures = "server";
      clients.default = {
        interface = netbirdInterface;
        port = 51820;
        config.ManagementURL = {
          Scheme = "https";
          Host = "netbird.asgard.michaelbrusegard.com:443";
        };
        login = {
          enable = true;
          inherit (config.secrets.netbird) setupKeyFile;
        };
      };
    };
  };
}
