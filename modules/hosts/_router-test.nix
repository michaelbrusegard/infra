{
  pkgs,
  lib,
}:
let
  probe = pkgs.writeShellApplication {
    name = "probe";
    runtimeInputs = [
      pkgs.socat
      pkgs.coreutils
    ];
    text = ''
      proto=$1
      host=$2
      port=$3
      case $host in
        *:*) address="[$host]" ;;
        *) address=$host ;;
      esac
      errors=$(mktemp)
      if output=$(echo probe | timeout 6 socat -T2 - "''${proto^^}:$address:$port,connect-timeout=2" 2>"$errors"); then
        reply=$(head -n 1 <<<"$output" | tr -d '\r')
        if [ "$proto" = tcp ] || [ -n "$reply" ]; then
          verdict="answered $reply"
        else
          verdict=silent
        fi
      elif grep -q "Connection refused" "$errors"; then
        verdict=refused
      else
        verdict=silent
      fi
      rm -f "$errors"
      echo "$proto $host $port $verdict"
    '';
  };

  probeBatch = pkgs.writeShellApplication {
    name = "probe-batch";
    runtimeInputs = [
      probe
      pkgs.findutils
    ];
    text = ''
      xargs -P 64 -L 1 probe
    '';
  };

  reply = pkgs.writeShellScript "whoami-reply" ''
    echo "''${WHOAMI_ADDRESS:-''${SOCAT_SOCKADDR:--}} $SOCAT_PEERADDR"
  '';

  whoamiService =
    {
      proto,
      port,
      address ? null,
    }:
    let
      family = if address == null || lib.hasInfix ":" address then "6" else "4";
      socket = if proto == "tcp" then "LISTEN" else "RECVFROM";
      bind =
        if address == null then
          "ipv6only=0"
        else if family == "6" then
          "bind=[${address}]"
        else
          "bind=${address}";
    in
    lib.nameValuePair
      "whoami-${proto}-${toString port}-${
        lib.replaceStrings [ ":" "." ] [ "-" "-" ] (if address == null then "any" else address)
      }"
      {
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        # Binding fails until the address has passed duplicate address detection.
        startLimitIntervalSec = 0;
        # A datagram socket cannot tell which address it was reached at, so a
        # bound listener names its own.
        environment.WHOAMI_ADDRESS = toString address;
        serviceConfig = {
          ExecStart = "${lib.getExe pkgs.socat} ${lib.toUpper proto}${family}-${socket}:${toString port},${bind},fork,reuseaddr EXEC:${reply}";
          Restart = "always";
          RestartSec = 1;
        };
      };
  # Every VM gets the probe tools; a router keeps its own firewall, endpoints
  # turn theirs off so every verdict belongs to the router under test.
  probeModule = {
    environment.systemPackages = [
      probe
      probeBatch
      pkgs.socat
    ];
    documentation.enable = false;
  };

  # Answers each connection or datagram with the address it arrived at and the
  # source address it came from, so a probe sees both ends of any NAT.
  whoami = listeners: {
    systemd.services = lib.listToAttrs (map whoamiService listeners);
  };
in
{
  # Nix lists are untyped, so hand the test script tuples it can type-check.
  pythonTuples =
    rows:
    "[${
      lib.concatMapStringsSep ", " (row: "(${lib.concatMapStringsSep ", " builtins.toJSON row})") rows
    }]";

  inherit probeModule whoami;

  # A host on one of the router's networks, leased by the router and
  # answering on tcp/7000.
  endpoint =
    {
      vlan,
      tag ? null,
    }:
    { lib, ... }:
    let
      interface = if tag == null then "uplink" else "tagged";
    in
    {
      imports = [
        probeModule
        (whoami [
          {
            proto = "tcp";
            port = 7000;
          }
        ])
      ];
      virtualisation.interfaces.uplink.vlan = vlan;
      networking = {
        useDHCP = false;
        firewall.enable = false;
        vlans = lib.optionalAttrs (tag != null) {
          tagged = {
            id = tag;
            interface = "uplink";
          };
        };
        interfaces.${interface}.useDHCP = true;
      };
      # The untagged side of the trunk is the router's trusted bridge; an address
      # there would let this VM reach it without crossing the router.
      boot.kernel.sysctl = lib.optionalAttrs (tag != null) {
        "net.ipv6.conf.uplink.disable_ipv6" = 1;
      };
    };

  # The ISP and the rest of the internet on the router's WAN port: hands out
  # the WAN lease and a router advertisement, and answers on tcp/7000 plus the
  # given listeners.
  internet = listeners: {
    imports = [
      probeModule
      (whoami (
        [
          {
            proto = "tcp";
            port = 7000;
          }
        ]
        ++ listeners
      ))
    ];
    virtualisation.interfaces.wan.vlan = 1;
    environment.systemPackages = [ pkgs.nmap ];
    # Everything beyond this host is unreachable and says so at once, so the
    # router's resolvers and blocklist downloads fail fast instead of timing out.
    boot.kernel.sysctl = {
      "net.ipv4.conf.all.forwarding" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      "net.ipv4.icmp_ratelimit" = 0;
      "net.ipv6.icmp.ratelimit" = 0;
    };
    networking = {
      useDHCP = false;
      firewall.enable = false;
      interfaces.wan = {
        ipv4.addresses = [
          {
            address = "198.51.100.1";
            prefixLength = 24;
          }
        ];
        ipv6.addresses = [
          {
            address = "2001:db8:ffff::1";
            prefixLength = 64;
          }
        ];
      };
      localCommands = ''
        ip route add unreachable default
        ip -6 route add unreachable default
      '';
    };
    services.dnsmasq = {
      enable = true;
      resolveLocalQueries = false;
      settings = {
        port = 0;
        interface = "wan";
        bind-interfaces = true;
        enable-ra = true;
        dhcp-range = [
          "198.51.100.100,198.51.100.199,1h"
          "::,constructor:wan,ra-only"
        ];
      };
    };
  };

  testHelpers = ''
    import contextlib
    import ipaddress
    import re
    import shlex
    import time
    from dataclasses import dataclass


    @dataclass
    class Flow:
        rule: str
        proto: str
        host: str
        port: int
        allowed: bool
        local: str | None = None
        peers: frozenset | None = None


    def allow(rule, proto, host, port, local=None, peers=None):
        return Flow(rule, proto, host, port, True, local, frozenset(peers) if peers else None)


    def deny(rule, proto, host, port):
        return Flow(rule, proto, host, port, False)


    def normalise(address):
        parsed = ipaddress.ip_address(address.strip("[]"))
        if isinstance(parsed, ipaddress.IPv6Address) and parsed.ipv4_mapped:
            parsed = parsed.ipv4_mapped
        return str(parsed)


    def addresses(node, interface, version):
        output = node.succeed(f"ip -{version} -o addr show dev {interface} scope global")
        return [line.split()[3].split("/")[0] for line in output.splitlines()]


    def wait_for_address(node, interface, prefix):
        node.wait_until_succeeds(f"ip -o addr show dev {interface} scope global -tentative | grep -q ' {prefix}'", timeout=120)
        version = 6 if ":" in prefix else 4
        output = node.succeed(f"ip -{version} -o addr show dev {interface} scope global -tentative")
        stable = [line for line in output.splitlines() if "temporary" not in line]
        return next(
            line.split()[3].split("/")[0]
            for line in stable
            if line.split()[3].startswith(prefix)
        )


    def run_probes(src, flows):
        targets = "\n".join(f"{flow.proto} {flow.host} {flow.port}" for flow in flows)
        output = src.succeed(f"printf '%s\\n' {shlex.quote(targets)} | probe-batch")
        results = {}
        for line in output.splitlines():
            proto, host, port, verdict, *reply = line.split()
            results[(proto, host, int(port))] = (verdict, reply)
        return results


    def explain(flow, verdict, reply):
        if not flow.allowed:
            return None if verdict == "silent" else f"expected dropped, got {verdict} {' '.join(reply)}".rstrip()
        if verdict == "silent":
            return "expected reachable, got silence"
        if flow.local or flow.peers:
            if verdict != "answered" or len(reply) != 2:
                return f"expected an answer naming both ends, got {verdict} {' '.join(reply)}".rstrip()
            if flow.local and normalise(reply[0]) != normalise(flow.local):
                return f"answered by {normalise(reply[0])}, expected {flow.local}"
            peer = normalise(reply[1])
            if flow.peers and peer not in {normalise(p) for p in flow.peers}:
                return f"seen from {peer}, expected one of {sorted(flow.peers)}"
        return None


    def check(src, flows, attempts=3):
        pending = list(flows)
        for attempt in range(attempts):
            results = run_probes(src, pending)
            broken = []
            for flow in pending:
                verdict, reply = results[(flow.proto, flow.host, flow.port)]
                problem = explain(flow, verdict, reply)
                if problem:
                    broken.append((flow, problem))
            if not broken:
                return
            pending = [flow for flow, _ in broken]
            if attempt + 1 < attempts:
                time.sleep(2)
        raise AssertionError(
            f"{len(broken)} rule(s) broken from {src.name}:\n"
            + "\n".join(
                f"  {flow.rule}: {flow.proto}/{flow.port} to {flow.host}: {problem}"
                for flow, problem in broken
            )
        )


    def listening(node):
        sockets = set()
        for line in node.succeed("ss -Hlntu").splitlines():
            netid, _, _, _, local, *_ = line.split()
            address, _, port = local.rpartition(":")
            address = address.strip("[]").split("%")[0]
            if address == "*" or not ipaddress.ip_address(address).is_loopback:
                sockets.add((netid, int(port)))
        return sockets


    def check_wan_surface(router, prober, router_addresses, internal_addresses, opened, forwarded=frozenset()):
        exposed = [
            allow(f"{rule} opens {proto}/{port} on WAN", proto, host, port)
            for (proto, port), rule in opened.items()
            for host in router_addresses
        ]
        hidden = [
            deny(f"{proto}/{port} listens on {router.name} and must stay closed from WAN", proto, host, port)
            for proto, port in sorted(listening(router) - set(opened) - set(forwarded))
            for host in router_addresses + internal_addresses
        ]
        check(prober, exposed + hidden)


    def check_tcp_sweep(prober, host, expected, rule):
        output = prober.succeed(f"nmap -n -Pn -sS -p- --max-retries 1 --min-rate 10000 -oG - {host}")
        reachable = {int(port) for port in re.findall(r"(\d+)/(?:open|closed)/tcp", output)}
        unexpected = sorted(reachable - set(expected))
        assert not unexpected, f"{rule}: TCP ports {unexpected} on {host} answer from WAN"
        summarised = re.findall(r"Ignored State: (open|closed) \((\d+)\)", output)
        assert not summarised, f"{rule}: {summarised} more TCP ports on {host} answer from WAN"


    def settle(node, command):
        with contextlib.suppress(Exception):
            node.wait_until_succeeds(command, timeout=60)


    def check_lease(node, interface, prefix, gateway, name, answer, zone):
        address = wait_for_address(node, interface, prefix)
        settle(node, f"ip -4 route show default | grep -q 'via {gateway}'")
        settle(node, f"grep -q 'nameserver {gateway}' /etc/resolv.conf")
        routes = node.succeed("ip -4 route show default")
        assert f"via {gateway}" in routes, f"dnsmasq dhcp-option router for {zone}: default route is {routes!r}, expected via {gateway}"
        resolvers = node.succeed("cat /etc/resolv.conf")
        assert f"nameserver {gateway}" in resolvers, f"dnsmasq dhcp-option dns-server for {zone}: resolv.conf is {resolvers!r}"
        node.wait_until_succeeds(f"getent ahostsv4 {name} | grep -q '^{answer} '", timeout=60)
        return address
  '';
}
