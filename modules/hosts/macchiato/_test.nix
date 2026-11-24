{
  pkgs,
  lib,
  routerModules,
}: let
  support = import ../_router-test.nix {inherit pkgs lib;};
  inherit (support) endpoint internet probeModule pythonTuples whoami;

  sshPort = 2222;
  routerName = "router.asgard.michaelbrusegard.com";

  # The cluster VIPs macchiato forwards to, held by one server VM in place of
  # the Cilium nodes that announce them over BGP.
  vips = {
    publicGateway = ["10.0.188.2" "fd7a:115c:a1e0:188::2"];
    stalwartEdge = ["10.0.188.12" "fd7a:115c:a1e0:188::12"];
    netbirdCoturn = ["10.0.188.34" "fd7a:115c:a1e0:188::34"];
    minecraftRouter = ["10.0.188.50" "fd7a:115c:a1e0:188::50"];
    k8sGateway = ["10.0.188.5" "fd7a:115c:a1e0:188::5"];
  };
  conditionalZones = ["asgard.michaelbrusegard.com" "manafishrov.com" "eldians.com"];
  nextcloudEturnal = ["10.0.187.3" "fd7a:115c:a1e0:187::3"];

  # The WAN surface this router is meant to have, written out by hand so that a
  # new forward or a newly opened port fails here until it is added on purpose.
  forwards = [
    ["publicPortForwards" "tcp" 80 vips.publicGateway]
    ["publicPortForwards" "tcp" 443 vips.publicGateway]
    ["publicPortForwards" "tcp" 25 vips.stalwartEdge]
    ["publicPortForwards" "tcp" 2525 vips.stalwartEdge]
    ["publicPortForwards" "udp" 3478 vips.netbirdCoturn]
    ["publicPortForwards" "tcp" 25565 vips.minecraftRouter]
    ["publicPortForwards" "udp" 5349 nextcloudEturnal]
    ["publicPortForwards" "tcp" 5349 nextcloudEturnal]
    # Both ends of the relay range, which must arrive with its port unchanged.
    ["turnRelayForward" "udp" 49152 nextcloudEturnal]
    ["turnRelayForward" "udp" 65535 nextcloudEturnal]
  ];
  opened = [
    ["tcp" sshPort "services.openssh.openFirewall"]
    ["udp" 5353 "services.avahi.openFirewall"]
    ["udp" 51820 "services.netbird.clients.default.port"]
  ];

  serverListeners =
    [
      {
        proto = "tcp";
        port = 7000;
      }
    ]
    ++ lib.concatMap (
      forward: let
        proto = lib.elemAt forward 1;
        port = lib.elemAt forward 2;
      in
        if proto == "tcp"
        then [{inherit proto port;}]
        else map (address: {inherit proto port address;}) (lib.elemAt forward 3)
    )
    forwards;

  hostAddresses = prefixLength: map (address: {inherit address prefixLength;});
in
  pkgs.testers.runNixOSTest {
    name = "macchiato-network";

    node = {
      pkgsReadOnly = false;
      specialArgs = {
        users = [];
        isWsl = false;
      };
    };

    nodes = {
      # Macchiato's whole host configuration on VM NICs carrying the real
      # interface names, so its networking module is imported unchanged.
      macchiato = {lib, ...}: {
        imports = routerModules ++ [probeModule];
        options.secrets = lib.mkOption {type = lib.types.attrs;};
        config = {
          secrets = {
            openssh.ports = [sshPort];
            wakeOnLan.ristretto.port = "22";
            cloudflare-dyndns.apiTokenFile = "/dev/null";
            netbird.setupKeyFile = "/dev/null";
            homebridge.settings.bridge = {
              username = "0E:00:00:00:00:00";
              pin = "000-00-000";
            };
          };

          virtualisation = {
            memorySize = 1536;
            interfaces = {
              enp2s0.vlan = 1;
              enp3s0.vlan = 2;
              enp4s0.vlan = 3;
              enp5s0.vlan = 4;
              enp1s0f0.vlan = 5;
              enp1s0f1.vlan = 6;
            };
          };

          # The VM boots its kernel directly from a throwaway disk.
          boot.lanzaboote.enable = lib.mkForce false;
          disko.enableConfig = false;
          environment.persistence = lib.mkForce {};
          # The test driver defines the same value, and the option accepts only
          # one definition.
          boot.kernel.sysctl."kernel.hung_task_timeout_secs" = lib.mkForce 600;

          services = {
            alloy.enable = lib.mkForce false;
            cloudflare-dyndns.enable = lib.mkForce false;
            fail2ban.enable = lib.mkForce false;
            homebridge.enable = lib.mkForce false;
            mosquitto.enable = lib.mkForce false;
            prometheus.exporters.node.enable = lib.mkForce false;
            unifi.enable = lib.mkForce false;
          };

          # Their options open firewall ports the test asserts, so only the
          # daemons stop: an absent listener answers with a refusal, which tells
          # an open port from a dropped one.
          systemd.services = {
            avahi-daemon.enable = lib.mkForce false;
            netbird-default.enable = lib.mkForce false;
            netbird-default-login.enable = lib.mkForce false;
            zigbee2mqtt.enable = lib.mkForce false;
          };
          systemd.sockets.avahi-daemon.enable = lib.mkForce false;

          # Stands in for the routes Cilium announces over BGP.
          networking.interfaces.br_servers = {
            ipv4.routes = [
              {
                address = "10.0.188.0";
                prefixLength = 24;
                via = lib.elemAt nextcloudEturnal 0;
              }
            ];
            ipv6.routes = [
              {
                address = "fd7a:115c:a1e0:188::";
                prefixLength = 64;
                via = lib.elemAt nextcloudEturnal 1;
              }
            ];
          };
        };
      };

      internet = internet [];

      client = endpoint {vlan = 2;};

      iot = endpoint {
        vlan = 3;
        tag = 189;
      };

      guest = endpoint {
        vlan = 3;
        tag = 190;
      };

      server = {lib, ...}: {
        imports = [probeModule (whoami serverListeners)];
        virtualisation.interfaces.uplink.vlan = 4;
        networking = {
          useDHCP = false;
          firewall.enable = false;
          interfaces.uplink = {
            ipv4.addresses =
              hostAddresses 24 [(lib.elemAt nextcloudEturnal 0)]
              ++ hostAddresses 32 (map lib.head (lib.attrValues vips));
            ipv6.addresses =
              hostAddresses 64 [(lib.elemAt nextcloudEturnal 1)]
              ++ hostAddresses 128 (map lib.last (lib.attrValues vips));
          };
          defaultGateway = {
            address = "10.0.187.1";
            interface = "uplink";
          };
          defaultGateway6 = {
            address = "fd7a:115c:a1e0:187::1";
            interface = "uplink";
          };
        };
        # Stands in for k8s-gateway, which blocky forwards the cluster zones to.
        services.dnsmasq = {
          enable = true;
          resolveLocalQueries = false;
          settings = {
            no-resolv = true;
            address = map (zone: "/${zone}/${lib.elemAt vips.publicGateway 0}") conditionalZones;
          };
        };
      };
    };

    testScript = ''
      ${support.testHelpers}

      internet6 = "2001:db8:ffff::1"
      server4, server6 = ${builtins.toJSON nextcloudEturnal}
      vip4, vip6 = ${builtins.toJSON vips.publicGateway}
      forwards = ${pythonTuples (map (forward: lib.take 3 forward ++ lib.elemAt forward 3) forwards)}
      opened = {(proto, port): rule for proto, port, rule in ${pythonTuples opened}}
      relay_range = range(49152, 65536)
      gateways = [
          "10.0.186.1", "10.0.187.1", "10.0.189.1", "10.0.190.1",
          "fd7a:115c:a1e0:186::1", "fd7a:115c:a1e0:187::1", "fd7a:115c:a1e0:189::1", "fd7a:115c:a1e0:190::1",
      ]

      start_all()

      with subtest("WAN lease and router advertisement"):
          wan4 = wait_for_address(macchiato, "enp2s0", "198.51.100.")
          wan6 = wait_for_address(macchiato, "enp2s0", "2001:db8:ffff:")
          internet.succeed(f"ip route add 10.0.0.0/8 via {wan4}")
          internet.succeed(f"ip -6 route add fd7a:115c:a1e0::/48 via {wan6}")

      with subtest("dnsmasq leases and blocky answers on every client network"):
          client4 = check_lease(client, "uplink", "10.0.186.", "10.0.186.1", "${routerName}", "10.0.186.1", "br_clients")
          iot4 = check_lease(iot, "tagged", "10.0.189.", "10.0.189.1", "${routerName}", "10.0.186.1", "iot")
          guest4 = check_lease(guest, "tagged", "10.0.190.", "10.0.190.1", "${routerName}", "10.0.186.1", "guest")
          client6 = wait_for_address(client, "uplink", "fd7a:115c:a1e0:186:")
          iot6 = wait_for_address(iot, "tagged", "fd7a:115c:a1e0:189:")
          guest6 = wait_for_address(guest, "tagged", "fd7a:115c:a1e0:190:")
          server.wait_for_unit("multi-user.target")
          for zone in ${builtins.toJSON conditionalZones}:
              answer = client.succeed(f"getent ahostsv4 cluster.{zone} || true")
              assert answer.startswith(vip4 + " "), f"blocky conditional.mapping {zone} -> k8s-gateway: got {answer!r}"

      masquerade = 'networking.nat masquerades out of "enp2s0"'
      native = "IPv6 egress is routed without NAT66"

      with subtest("br_clients"):
          check(client, [
              allow(masquerade, "tcp", "198.51.100.1", 7000, peers=[wan4]),
              allow(native, "tcp", internet6, 7000, peers=addresses(client, "uplink", 6)),
              allow('iifname "br_clients" oifname "br_servers" accept', "tcp", server4, 7000, peers=[client4]),
              allow('iifname { "br_clients", "br_servers" } ip daddr 10.0.188.0/24 accept', "tcp", vip4, 443, local=vip4),
              allow('iifname { "br_clients", "br_servers" } ip6 daddr fd7a:115c:a1e0:188::/64 accept', "tcp", vip6, 443, local=vip6),
              allow('iifname "br_clients" oifname "iot" accept', "tcp", iot4, 7000, peers=[client4]),
              allow('iifname "br_clients" oifname "iot" accept', "tcp", iot6, 7000),
              deny("default-drop forward policy keeps br_clients out of guest", "tcp", guest4, 7000),
              allow("trustedInterfaces br_clients reaches router services", "tcp", "10.0.186.1", 4000),
          ])

      with subtest("br_servers"):
          check(server, [
              allow(masquerade, "tcp", "198.51.100.1", 7000, peers=[wan4]),
              allow('iifname "br_servers" oifname "br_clients" accept', "tcp", client4, 7000, peers=[server4]),
              deny("default-drop forward policy keeps br_servers out of iot", "tcp", iot4, 7000),
              deny("default-drop forward policy keeps br_servers out of guest", "tcp", guest4, 7000),
          ])

      zones = {
          "iot": (iot, "10.0.189.1", guest4),
          "guest": (guest, "10.0.190.1", iot4),
      }
      for zone, (node, gateway, other4) in zones.items():
          with subtest(zone):
              isolated = f'{zone}: internet only, internal traffic hits the default-drop policy'
              check(node, [
                  allow(f'iifname "{zone}" oifname "enp2s0" accept; {masquerade}', "tcp", "198.51.100.1", 7000, peers=[wan4]),
                  allow(f'iifname "{zone}" oifname "enp2s0" accept; {native}', "tcp", internet6, 7000, peers=addresses(node, "tagged", 6)),
                  deny(isolated, "tcp", client4, 7000),
                  deny(isolated, "tcp", client6, 7000),
                  deny(isolated, "tcp", server4, 7000),
                  deny(isolated, "tcp", vip4, 443),
                  deny(isolated, "tcp", vip6, 443),
                  deny(isolated, "tcp", other4, 7000),
                  allow(f"firewall.interfaces.{zone} allows DNS", "tcp", gateway, 53),
                  deny(f"firewall.interfaces.{zone} allows only DNS and DHCP", "tcp", gateway, 4000),
                  deny(f"firewall.interfaces.{zone} allows only DNS and DHCP", "tcp", gateway, 8444),
                  deny(f"firewall.interfaces.{zone} allows only DNS and DHCP", "tcp", "10.0.186.1", 4000),
              ])

      with subtest("iot resolves only through the router"):
          outside_dns = 'iifname "iot" oifname "enp2s0" th dport { 53, 853 } drop'
          check(iot, [
              deny(outside_dns, "tcp", "198.51.100.1", 53),
              deny(outside_dns, "udp", "198.51.100.1", 53),
              deny(outside_dns, "tcp", "198.51.100.1", 853),
              deny(outside_dns, "tcp", internet6, 53),
              deny(outside_dns, "udp", internet6, 53),
          ])

      with subtest("WAN"):
          forwarded = []
          for rule, proto, port, target4, target6 in forwards:
              forwarded += [
                  allow(f"{rule} to {target4}", proto, wan4, port, local=target4, peers=["198.51.100.1"]),
                  allow(f"{rule} to {target6}", proto, wan6, port, local=target6, peers=[internet6]),
              ]
          blocked = 'iifname "enp2s0" drop'
          check(internet, forwarded + [
              deny(blocked, "tcp", client4, 7000),
              deny(blocked, "tcp", client6, 7000),
              deny(blocked, "tcp", server4, 7000),
              deny(blocked, "tcp", server6, 7000),
              deny(blocked, "tcp", iot6, 7000),
              deny(blocked, "tcp", guest6, 7000),
          ])
          forwarded_ports = {(proto, port) for _, proto, port, _, _ in forwards} | {("udp", port) for port in relay_range}
          check_wan_surface(macchiato, internet, [wan4, wan6], gateways, opened, forwarded_ports)
          check_tcp_sweep(internet, wan4, {port for proto, port in forwarded_ports | set(opened) if proto == "tcp"}, "WAN TCP surface")
    '';
  }
