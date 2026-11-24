{
  pkgs,
  lib,
  routerModules,
}: let
  support = import ../_router-test.nix {inherit pkgs lib;};
  inherit (support) endpoint internet probeModule pythonTuples;

  sshPort = 2222;
  routerName = "router.midgard.michaelbrusegard.com";

  # The WAN surface this router is meant to have, written out by hand so that a
  # newly opened port fails here until it is added on purpose.
  opened = [
    ["tcp" 443 "firewall.interfaces.enp7s0 for the NetBird relay"]
    ["tcp" 25 "smtp-backup opens SMTP on enp7s0"]
    ["udp" 51820 "services.netbird.clients.default.port"]
  ];

  # Destinations the IoT VLAN may reach on the internet.
  iotEgress = [
    ["tcp" 80]
    ["tcp" 443]
    ["udp" 123]
    ["udp" 443]
  ];
in
  pkgs.testers.runNixOSTest {
    name = "cortado-network";

    node = {
      pkgsReadOnly = false;
      specialArgs = {
        users = [];
        isWsl = false;
      };
    };

    nodes = {
      # Cortado's whole host configuration on VM NICs carrying the real
      # interface names, so its networking module is imported unchanged.
      cortado = {lib, ...}: {
        imports = routerModules ++ [probeModule];
        options.secrets = lib.mkOption {type = lib.types.attrs;};
        config = {
          secrets = {
            openssh.ports = [sshPort];
            acme.email = "acme@example.test";
            cloudflare-dyndns.apiTokenFile = "/dev/null";
            netbird = {
              setupKeyFile = "/dev/null";
              environmentFile = "/dev/null";
            };
            smtp-backup = {
              clientCertificateFile = "/dev/null";
              clientKeyFile = "/dev/null";
            };
          };

          virtualisation = {
            memorySize = 1536;
            interfaces = {
              enp7s0.vlan = 1;
              enp4s0.vlan = 2;
              enp5s0.vlan = 3;
              enp1s0.vlan = 4;
              enp2s0.vlan = 5;
              enp6s0.vlan = 6;
            };
          };

          # The VM boots its kernel directly from a throwaway disk.
          boot.lanzaboote.enable = lib.mkForce false;
          disko.enableConfig = false;
          environment.persistence = lib.mkForce {};
          # The test driver defines the same value, and the option accepts only
          # one definition.
          boot.kernel.sysctl."kernel.hung_task_timeout_secs" = lib.mkForce 600;

          # Certificates cannot be issued offline, and nothing here needs TLS.
          security.acme.certs = lib.mkForce {};
          local.netbirdRelay.enable = lib.mkForce false;
          services = {
            caddy.enable = lib.mkForce false;
            cloudflare-dyndns.enable = lib.mkForce false;
            fail2ban.enable = lib.mkForce false;
            home-assistant.enable = lib.mkForce false;
            postfix.enable = lib.mkForce false;
            prometheus.exporters.node.enable = lib.mkForce false;
            unifi.enable = lib.mkForce false;
          };

          # The client's options open a firewall port the test asserts, so
          # only the daemon stops: an absent listener answers with a refusal,
          # which tells an open port from a dropped one.
          systemd.services = {
            netbird-default.enable = lib.mkForce false;
            netbird-default-login.enable = lib.mkForce false;
          };
        };
      };

      internet = internet (map (destination: {
          proto = lib.elemAt destination 0;
          port = lib.elemAt destination 1;
        })
        iotEgress);

      lan = endpoint {vlan = 2;};

      iot = endpoint {
        vlan = 3;
        tag = 17;
      };
    };

    testScript = ''
      ${support.testHelpers}

      internet4 = "198.51.100.1"
      internet6 = "2001:db8:ffff::1"
      opened = {(proto, port): rule for proto, port, rule in ${pythonTuples opened}}
      iot_egress = ${pythonTuples iotEgress}
      gateways = ["10.0.15.1", "10.0.17.1", "fd7a:115c:a1e0:15::1", "fd7a:115c:a1e0:17::1"]

      start_all()

      with subtest("WAN lease and router advertisement"):
          wan4 = wait_for_address(cortado, "enp7s0", "198.51.100.")
          wan6 = wait_for_address(cortado, "enp7s0", "2001:db8:ffff:")
          internet.succeed(f"ip route add 10.0.0.0/8 via {wan4}")
          internet.succeed(f"ip -6 route add fd7a:115c:a1e0::/48 via {wan6}")

      with subtest("dnsmasq leases and blocky answers on both networks"):
          lan4 = check_lease(lan, "uplink", "10.0.15.", "10.0.15.1", "${routerName}", "10.0.15.1", "trusted")
          iot4 = check_lease(iot, "tagged", "10.0.17.", "10.0.17.1", "${routerName}", "10.0.15.1", "iot")
          lan6 = wait_for_address(lan, "uplink", "fd7a:115c:a1e0:15:")
          iot6 = wait_for_address(iot, "tagged", "fd7a:115c:a1e0:17:")

      masquerade = 'networking.nat masquerades out of "enp7s0"'
      native = "IPv6 egress is routed without NAT66"

      with subtest("br_lan"):
          check(lan, [
              allow(f'iifname "br_lan" oifname "enp7s0" accept; {masquerade}', "tcp", internet4, 7000, peers=[wan4]),
              allow(f'iifname "br_lan" oifname "enp7s0" accept; {native}', "tcp", internet6, 7000, peers=addresses(lan, "uplink", 6)),
              allow('iifname "br_lan" oifname "iot" accept', "tcp", iot4, 7000, peers=[lan4]),
              allow('iifname "br_lan" oifname "iot" accept', "tcp", iot6, 7000),
              allow("trustedInterfaces br_lan reaches SSH on the router", "tcp", "10.0.15.1", ${toString sshPort}),
          ])

      with subtest("iot"):
          egress = {
              "tcp": 'iifname "iot" oifname "enp7s0" tcp dport { 80, 443 } accept',
              "udp": 'iifname "iot" oifname "enp7s0" udp dport { 123, 443 } accept',
          }
          isolated = "default-drop forward policy keeps iot out of br_lan"
          check(iot, [
              allow(f"{egress[proto]}; {masquerade}", proto, internet4, port, peers=[wan4])
              for proto, port in iot_egress
          ] + [
              allow(f"{egress['tcp']}; {native}", "tcp", internet6, 443, peers=addresses(iot, "tagged", 6)),
              deny(isolated, "tcp", lan4, 7000),
              deny(isolated, "tcp", lan6, 7000),
              allow("firewall.interfaces.iot allows DNS", "tcp", "10.0.17.1", 53),
              deny("openssh.openFirewall = false keeps SSH off iot", "tcp", "10.0.17.1", ${toString sshPort}),
              deny("openssh.openFirewall = false keeps SSH off iot", "tcp", "10.0.15.1", ${toString sshPort}),
              deny("firewall.interfaces.iot allows only DNS and DHCP", "tcp", "10.0.17.1", 4000),
          ])

      with subtest("WAN"):
          blocked = 'iifname "enp7s0" drop'
          check(internet, [
              deny(blocked, "tcp", lan4, 7000),
              deny(blocked, "tcp", lan6, 7000),
              deny(blocked, "tcp", iot4, 7000),
              deny(blocked, "tcp", iot6, 7000),
          ])
          check_wan_surface(cortado, internet, [wan4, wan6], gateways, opened)
          check_tcp_sweep(internet, wan4, {port for proto, port in opened if proto == "tcp"}, "WAN TCP surface")
    '';
  }
