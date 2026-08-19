{pkgs, ...}: let
  bypassTable = "8228";
  interface = "tetherfuse";
  proxyIp = "192.168.49.1";
  proxyPort = "8228";
  service = "tetherfuse-tunnel.service";

  setup = pkgs.writeShellApplication {
    name = "tetherfuse-setup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.iproute2
      pkgs.systemd
    ];
    text = ''
      resolvectl revert ${interface} 2>/dev/null || true
      ip -4 rule del pref 103 to ${proxyIp}/32 lookup ${bypassTable} 2>/dev/null || true
      ip -4 rule del pref 104 2>/dev/null || true
      ip -6 rule del pref 104 2>/dev/null || true
      ip -4 route flush table ${bypassTable} 2>/dev/null || true
      ip link delete ${interface} 2>/dev/null || true

      ip tuntap add name ${interface} mode tun
      ip address replace 10.255.255.1/32 dev ${interface}
      ip link set ${interface} up

      # The proxy connection itself must never enter the tunnel. A separate
      # table keeps this route effective even while NetworkManager removes the
      # Wi-Fi Direct connection during disconnect.
      ip -4 route replace table ${bypassTable} ${proxyIp}/32 dev wlan0
      ip -4 rule add pref 103 to ${proxyIp}/32 lookup ${bypassTable}

      # NetBird normally consults the main table before its own routing table.
      # The tunnel's two /1 routes would therefore shadow NetBird network
      # routes. Clone NetBird's marked lookup ahead of the main-table rule.
      for family in -4 -6; do
        rule="$({ ip "$family" rule show || true; } \
          | sed -n 's/.*not from all fwmark \([^ ]*\) lookup \([^ ]*\).*/\1 \2/p' \
          | head -n 1)"
        if [ -n "$rule" ]; then
          read -r mark table <<< "$rule"
          ip "$family" rule add pref 104 not fwmark "$mark" lookup "$table"
        fi
      done

      ip -4 route replace 0.0.0.0/1 dev ${interface}
      ip -4 route replace 128.0.0.0/1 dev ${interface}
      ip -6 route replace ::/1 dev ${interface}
      ip -6 route replace 8000::/1 dev ${interface}

      # Keep systemd-resolved in charge so NetBird's route-specific DNS
      # domains continue to win over this catch-all virtual DNS link.
      resolvectl dns ${interface} 198.18.0.1
      resolvectl domain ${interface} '~.'
      resolvectl default-route ${interface} yes
    '';
  };

  cleanup = pkgs.writeShellApplication {
    name = "tetherfuse-cleanup";
    runtimeInputs = [
      pkgs.iproute2
      pkgs.systemd
    ];
    text = ''
      resolvectl revert ${interface} 2>/dev/null || true
      ip -4 rule del pref 103 to ${proxyIp}/32 lookup ${bypassTable} 2>/dev/null || true
      ip -4 rule del pref 104 2>/dev/null || true
      ip -6 rule del pref 104 2>/dev/null || true
      ip -4 route flush table ${bypassTable} 2>/dev/null || true
      ip link delete ${interface} 2>/dev/null || true
    '';
  };

  dispatcher = pkgs.writeShellScript "tetherfuse-dispatcher" ''
    if [ "$1" != "wlan0" ]; then
      exit 0
    fi

    case "$2:$CONNECTION_ID" in
      up:DIRECT-TF-Doppio)
        ${pkgs.systemd}/bin/systemctl start --no-block ${service}
        ;;
      up:*|down:DIRECT-TF-Doppio)
        ${pkgs.systemd}/bin/systemctl stop --no-block ${service}
        ;;
    esac
  '';
in {
  networking.networkmanager.dispatcherScripts = [
    {
      source = dispatcher;
      type = "basic";
    }
  ];

  systemd.services.tetherfuse-tunnel = {
    description = "Route traffic through the TetherFuseNet SOCKS5 proxy";
    after = [
      "NetworkManager.service"
      "netbird-default.service"
      "systemd-resolved.service"
    ];
    requires = ["systemd-resolved.service"];

    serviceConfig = {
      Type = "simple";
      ExecStartPre = "${setup}/bin/tetherfuse-setup";
      ExecStart = "${pkgs.tun2proxy}/bin/tun2proxy-bin --tun ${interface} --proxy socks5://${proxyIp}:${proxyPort} --dns virtual --ipv6-enabled --exit-on-fatal-error";
      ExecStopPost = "${cleanup}/bin/tetherfuse-cleanup";
      KillSignal = "SIGINT";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
}
