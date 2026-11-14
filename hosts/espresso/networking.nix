{config, ...}: let
  nodeMACs = {
    "espresso-0" = "c8:98:db:19:12:30";
    "espresso-1" = "b4:96:91:26:31:fa";
    "espresso-2" = "b4:96:91:ff:ff:ff";
  };
  nodeIPv6s = {
    "espresso-0" = "fd7a:115c:a1e0:187::2";
    "espresso-1" = "fd7a:115c:a1e0:187::3";
    "espresso-2" = "fd7a:115c:a1e0:187::4";
  };
in {
  boot.kernel.sysctl = {
    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv6.conf.all.accept_ra" = 2;
  };

  # Never restart dhcpcd during a switch; changes apply at the next boot.
  # Losing the node IP stalls every Mayastor NVMe-oF device, and a dhcpcd
  # started while they hang can wedge before it leases the address back.
  # That took espresso-2 offline until it was reset.
  systemd.services.dhcpcd.restartIfChanged = false;

  networking = {
    # Keep the leased address when dhcpcd stops. Otherwise restarting it
    # during a switch drops the node IP, and the kernel deletes Cilium's
    # routes to the other nodes' pod networks with it.
    dhcpcd.persistent = true;
    useDHCP = false;
    tempAddresses = "disabled";
    firewall.enable = false;
    defaultGateway6 = {
      address = "fd7a:115c:a1e0:187::1";
      interface = "lan0";
    };

    interfaces.lan0 = {
      useDHCP = true;
      tempAddress = "disabled";
      ipv6.addresses = [
        {
          address = nodeIPv6s.${config.networking.hostName};
          prefixLength = 64;
        }
      ];
    };
  };

  systemd.network.links."10-lan0" = {
    matchConfig.PermanentMACAddress = nodeMACs.${config.networking.hostName};
    linkConfig.Name = "lan0";
  };
}
