#!/usr/bin/env python3
"""Exercise the deployed init script against Linux policy routing, without a network.

Run with python3 on a Linux host allowing unprivileged user/network namespaces,
or with sudo in CI. Every probe gets a fresh namespace with two veth pairs;
no host routes, cluster resources, or external services are changed.
"""

from pathlib import Path
import re
import subprocess
import textwrap
import unittest


STATEFULSET = Path(__file__).resolve().parents[1] / "statefulset.yaml"

# Match the pod's Cilium gateways and NetBird v0.77.1 policy routing. Separate
# veth pairs let tests remove the tunnel without also removing the underlay.
SETUP = """\
set -eu
ip link set lo up
ip link add eth0 type veth peer name underlay-peer
ip link add wt0 type veth peer name tunnel-peer
for link in eth0 underlay-peer wt0 tunnel-peer; do
    ip link set "$link" up
done
ip addr add 10.42.0.131/32 dev eth0
ip route add 10.42.0.235 dev eth0
ip route add default via 10.42.0.235 dev eth0
ip -6 addr add fd42::8320/128 dev eth0 nodad
ip -6 route add fd42::441c dev eth0
ip -6 route add default via fd42::441c dev eth0
ip addr add 100.105.163.249/16 dev wt0
ip -6 addr add fdaf:859e:7392:ecc0::2/64 dev wt0 nodad
for family in -4 -6; do
    ip "$family" rule add pref 105 lookup main suppress_prefixlength 0
    ip "$family" rule add pref 110 not fwmark 0x1bd00 lookup 7120
    ip "$family" route add default dev wt0 table 7120
done

expect_route() {
    device="$1"
    shift
    route="$(ip "$@")"
    case " $route " in
        *" dev $device "*) ;;
        *) echo "expected $device: ip $*: $route" >&2; exit 1 ;;
    esac
}

expect_unreachable() {
    if route="$(ip "$@" 2>&1)"; then
        echo "unexpected route: ip $*: $route" >&2
        exit 1
    fi
    case "$route" in
        *"Network is unreachable"*|*"Network unreachable"*) ;;
        *) echo "unexpected lookup error: $route" >&2; exit 1 ;;
    esac
}
"""

TRANSPORT = """\
expect_route eth0 -4 route get 198.51.100.10 mark 0x1bd00
expect_route eth0 -6 route get 2001:db8:ffff::10 mark 0x1bd00
"""

CLUSTER = """\
expect_route eth0 -4 route get 10.42.2.56
expect_route eth0 -4 route get 10.43.0.10
expect_route eth0 -4 route get 10.0.188.1
expect_route eth0 -6 route get fd42::1234
expect_route eth0 -6 route get fd43::a
expect_route lo -4 route get 127.0.0.1
expect_route lo -6 route get ::1
"""

FAIL_CLOSED = """\
expect_unreachable -4 route get 198.51.100.10
expect_unreachable -6 route get 2001:db8:ffff::10
expect_unreachable -4 route get 198.51.100.10 mark 0x1bd01
expect_unreachable -6 route get 2001:db8:ffff::10 mark 0x1bd01
"""


class NetBirdEgressTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = STATEFULSET.read_text()
        container = cls.manifest.split("        - name: preserve-cluster-routes\n", 1)[1]
        container = container.split("          securityContext:\n", 1)[0]
        match = re.search(r"            - \|\n((?:              .*\n|\n)+)", container)
        if not match:
            raise AssertionError("could not extract the deployed routing init script")
        cls.init_script = textwrap.dedent(match.group(1))

    def probe(self, script):
        result = subprocess.run(
            ["unshare", "--user", "--map-root-user", "--net", "sh", "-ec",
             SETUP + "\n" + self.init_script + "\n" + script],
            capture_output=True,
            text=True,
            timeout=15,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_relay_transport_has_an_underlay_route(self):
        self.probe(TRANSPORT)

    def test_application_internet_uses_only_the_tunnel(self):
        self.probe("""\
expect_route wt0 -4 route get 198.51.100.10
expect_route wt0 -6 route get 2001:db8:ffff::10
expect_route wt0 -4 route get 198.51.100.10 mark 0x1bd01
expect_route wt0 -6 route get 2001:db8:ffff::10 mark 0x1bd01
test -z "$(ip -4 route show table main default)"
test -z "$(ip -6 route show table main default)"
""")

    def test_cluster_and_loopback_remain_local(self):
        self.probe(CLUSTER)

    def test_exit_route_withdrawal_fails_closed(self):
        self.probe("""\
ip -4 route flush table 7120
ip -6 route flush table 7120
""" + FAIL_CLOSED + TRANSPORT + CLUSTER)

    def test_tunnel_removal_fails_closed(self):
        self.probe("ip link del wt0\n" + FAIL_CLOSED + TRANSPORT + CLUSTER)

    def test_sidecar_routing_cleanup_fails_closed(self):
        self.probe("""\
for family in -4 -6; do
    ip "$family" route flush table 7120
    ip "$family" rule del pref 105
    ip "$family" rule del pref 110
done
ip link del wt0
""" + FAIL_CLOSED + TRANSPORT + CLUSTER)

    def test_application_containers_cannot_mark_transport_packets(self):
        # Linux permits SO_MARK with either CAP_NET_ADMIN or CAP_NET_RAW.
        # NET_RAW is in the container runtime's default capability set.
        containers = self.manifest.split("      containers:\n", 1)[1]
        containers = containers.split("      volumes:\n", 1)[0]
        for container in re.split(r"^        - name: ", containers, flags=re.MULTILINE)[1:]:
            name = container.splitlines()[0]
            with self.subTest(container=name):
                context = container.split("          securityContext:\n", 1)[1]
                self.assertRegex(context, r"drop:\n(?: +-[^\n]*\n)* +-(?: ALL| NET_RAW)\n")
                self.assertNotRegex(context, r"add:\n(?: +-[^\n]*\n)* +- NET_(?:ADMIN|RAW)\n")


if __name__ == "__main__":
    unittest.main()
