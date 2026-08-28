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
    "enp4s0" # port 3
    "enp5s0" # port 4
    "enp6s0" # port 5
  ];
  lanBridge = "br_lan";
in {
  networking = {
    useDHCP = false;
    enableIPv6 = false;
    nftables.enable = true;
    bridges.${lanBridge}.interfaces = lanInterfaces;

    nameservers = [
      "1.1.1.1"
      "9.9.9.9"
    ];

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
      };
    };

    nat = {
      enable = true;
      externalInterface = wanInterface;
      internalInterfaces = [lanBridge];
    };

    firewall = {
      enable = true;
      trustedInterfaces = [lanBridge];
      filterForward = true;
      extraForwardRules = ''
        iifname "${wanInterface}" drop
        iifname "${lanBridge}" oifname "${wanInterface}" accept
      '';
    };
  };

  # Trusted LAN access is covered by trustedInterfaces. Do not expose SSH on
  # the Monkeybrains WAN interface.
  services.openssh.openFirewall = lib.mkForce false;

  services.dnsmasq = {
    enable = true;
    settings = {
      interface = lanBridge;
      bind-interfaces = true;
      dhcp-authoritative = true;
      dhcp-range = "10.0.15.10,10.0.15.254,24h";
      dhcp-option = [
        "option:router,10.0.15.1"
        "option:dns-server,10.0.15.1"
      ];
      no-resolv = true;
      server = [
        "1.1.1.1"
        "9.9.9.9"
      ];
    };
  };

  # Keep the SSH port available to the firewall module even though it is only
  # reachable through the trusted LAN bridge.
  networking.firewall.interfaces.${lanBridge}.allowedTCPPorts = config.secrets.openssh.ports;
}
