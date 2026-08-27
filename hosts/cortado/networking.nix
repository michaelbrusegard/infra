{config, ...}: let
  # TODO(cortado): Replace these after collecting `ip -br link`. Use one of
  # the 10 GbE ports for the LAN trunk. The other four ports remain
  # intentionally unconfigured until their roles are known.
  wanInterface = "TODO_WAN";
  lanInterface = "TODO_10GB_LAN_TRUNK";
  iotInterface = "iot";
  netbirdInterface = "vpn_clients";
in {
  boot.kernel.sysctl = {
    "net.ipv6.conf.all.forwarding" = 1;
    # Forwarding normally disables WAN router advertisements. Value 2 keeps
    # them enabled so DHCPv6 prefix delegation can work when Monkeybrains
    # provides it.
    "net.ipv6.conf.${wanInterface}.accept_ra" = 2;
  };

  networking = {
    useDHCP = false;
    nftables.enable = true;

    nameservers = [
      "127.0.0.1"
      "::1"
      "1.1.1.1"
      "2606:4700:4700::1111"
    ];

    vlans.${iotInterface} = {
      id = 17;
      interface = lanInterface;
    };

    interfaces = {
      "${wanInterface}".useDHCP = true;

      # Native/untagged trusted network on the 10 GbE switch trunk.
      "${lanInterface}" = {
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

      # Tagged IoT network for the robot vacuum and other smart-home devices.
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

    # TODO(cortado): Verify Monkeybrains offers DHCPv6 prefix delegation and
    # adjust the requested layout if its delegated prefix is smaller than /63.
    dhcpcd = {
      enable = true;
      denyInterfaces = [lanInterface iotInterface];
      extraConfig = ''
        interface ${wanInterface}
          ia_na 1
          ia_pd 1 ${lanInterface}/0/64 ${iotInterface}/1/64
      '';
    };

    nat = {
      enable = true;
      externalInterface = wanInterface;
      internalInterfaces = [
        lanInterface
        iotInterface
        netbirdInterface
      ];
    };

    firewall = {
      enable = true;
      trustedInterfaces = [lanInterface];
      filterForward = true;
      allowedUDPPorts = [51820];

      extraForwardRules = ''
        # Block unsolicited inbound IPv4 and IPv6 traffic from Monkeybrains.
        iifname "${wanInterface}" drop

        # Trusted clients may reach the internet and initiate connections to
        # IoT devices. IoT devices cannot initiate connections back.
        iifname "${lanInterface}" oifname "${wanInterface}" accept
        iifname "${lanInterface}" oifname "${iotInterface}" accept

        # IoT devices receive internet access but no forwarded access to the
        # trusted network.
        iifname "${iotInterface}" oifname "${wanInterface}" accept

        # NetBird provides remote administration and optional access to both
        # SF networks. NetBird policy remains the outer authorization layer.
        iifname "${netbirdInterface}" oifname { "${lanInterface}", "${iotInterface}" } accept

        # Allow Cortado to act as a NetBird exit node if that route is enabled.
        iifname "${netbirdInterface}" oifname "${wanInterface}" accept
      '';

      interfaces = {
        "${iotInterface}" = {
          allowedTCPPorts = [53];
          # DNS, DHCP, SSDP, and mDNS discovery terminate on Cortado. No Avahi
          # reflector is enabled between the trusted and IoT networks.
          allowedUDPPorts = [53 67 1900 5353];
        };
        "${netbirdInterface}" = {
          # Blocky metrics/API, Home Assistant, UniFi proxy, and node exporter.
          # SSH is opened separately by the shared OpenSSH module.
          allowedTCPPorts = [4000 8123 8444 9100];
        };
      };
    };
  };

  services = {
    # Advertise native delegated IPv6 prefixes when Monkeybrains supplies one.
    radvd = {
      enable = true;
      config = ''
        interface ${lanInterface} {
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

    # Blocky owns DNS; dnsmasq only supplies DHCP leases and network options.
    dnsmasq = {
      enable = true;
      settings = {
        port = 0;
        bind-interfaces = true;
        interface = [lanInterface iotInterface];
        dhcp-authoritative = true;
        dhcp-range = [
          "set:trusted,10.0.15.10,10.0.15.254,24h"
          "set:iot,10.0.17.10,10.0.17.254,24h"
        ];
        dhcp-option = [
          "tag:trusted,option:router,10.0.15.1"
          "tag:trusted,option:dns-server,10.0.15.1"
          "tag:iot,option:router,10.0.17.1"
          "tag:iot,option:dns-server,10.0.17.1"
        ];
      };
    };

    blocky.settings.customDNS.mapping = {
      "cortado.home" = "10.0.15.1,fd7a:115c:a1e0:15::1";
      "home-assistant.home" = "10.0.15.1,fd7a:115c:a1e0:15::1";
      "unifi.home" = "10.0.15.1,fd7a:115c:a1e0:15::1";
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
        # TODO(cortado): Enable automatic login after adding Cortado's setup
        # key to infra-secrets. Until then, enroll it interactively once.
        login.enable = false;
      };
    };
  };

  environment.persistence."/persistent".directories = [
    config.services.netbird.clients.default.dir.state
  ];
}
