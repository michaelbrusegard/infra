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

  networking = {
    useDHCP = false;
    tempAddresses = "disabled";

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

    firewall = {
      allowedTCPPorts = [6443 6444 2379 2380 10250];
      trustedInterfaces = ["cilium_host" "cilium_net" "cilium_vxlan" "lxc*"];
    };
  };

  systemd.network.links."10-lan0" = {
    matchConfig.PermanentMACAddress = nodeMACs.${config.networking.hostName};
    linkConfig.Name = "lan0";
  };
}
