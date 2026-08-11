{
  config,
  pkgs,
  ...
}: let
  # Reserves a /120 slice of the ISP-delegated GUA /64 (announced on br_servers
  # via radvd) for SearXNG per-request source address rotation. Each engine
  # request leaves from a different address, so per-IP rate limits and CAPTCHAs
  # (DuckDuckGo, Brave, Google, Startpage) never accumulate on a single address.
  #
  # The slice is tagged with marker hextet 5ea7 to stay clear of SLAAC
  # addresses on the segment. The delegated prefix is dynamic, so the range is
  # derived at runtime from the on-link route the kernel installs from router
  # advertisements, and rendered into the searxng pod's settings.yml through a
  # hostPath file (gitops/espresso/apps/searxng/deployment.yaml).
  nodeIndex =
    {
      "espresso-0" = 0;
      "espresso-1" = 1;
      "espresso-2" = 2;
    }.${
      config.networking.hostName
    };

  rotationScript = pkgs.writeShellApplication {
    name = "searxng-ipv6-rotation";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      iproute2
    ];
    text = ''
      set -euo pipefail

      state_dir=/run/searxng
      range_file="$state_dir/ipv6-range"
      ndppd_conf="$state_dir/ndppd.conf"
      mkdir -p "$state_dir"

      # On-link GUA /64 from prefix delegation (global unicast starts with
      # 2xxx/3xxx, which also excludes the ULA prefixes on the segment)
      prefix=$(ip -6 route show dev lan0 \
        | grep -oE '^[23][0-9a-f]{0,3}(:[0-9a-f]{1,4}){3}::/64' \
        | head -n1 || true)
      if [ -z "$prefix" ]; then
        echo "no delegated GUA prefix on lan0 yet, keeping previous state"
        exit 0
      fi

      range="''${prefix%%::*}:5ea7:0:${toString nodeIndex}:0/120"
      previous=$(cat "$range_file" 2>/dev/null || true)
      if [ -n "$previous" ] && [ "$previous" != "$range" ]; then
        ip -6 route del local "$previous" dev lo 2>/dev/null || true
      fi
      ip -6 route replace local "$range" dev lo

      # The kernel does not answer neighbour solicitations for local routes,
      # so ndppd proxies NDP for the rotation range on lan0
      printf 'proxy lan0 {\n  router no\n  rule %s {\n    static\n  }\n}\n' \
        "$range" > "$ndppd_conf"

      if [ "$previous" != "$range" ]; then
        printf '%s\n' "$range" > "$range_file.tmp"
        mv "$range_file.tmp" "$range_file"
        echo "rotation range changed: ''${previous:-none} -> $range"
        systemctl restart searxng-ndppd.service
      fi
    '';
  };
in {
  boot.kernel.sysctl = {
    # Accept router advertisements on lan0 despite forwarding (k3s) being
    # enabled, so the node learns the delegated GUA prefix
    "net.ipv6.conf.lan0.accept_ra" = 2;
    # Allow binding any address inside the local-routed rotation range
    "net.ipv6.ip_nonlocal_bind" = 1;
  };

  systemd.services.searxng-ipv6-rotation = {
    description = "Maintain the SearXNG IPv6 source rotation range";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${rotationScript}/bin/searxng-ipv6-rotation";
    };
  };

  systemd.timers.searxng-ipv6-rotation = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "1min";
    };
  };

  # No wantedBy: started by searxng-ipv6-rotation once a range exists
  systemd.services.searxng-ndppd = {
    description = "NDP proxy for the SearXNG IPv6 rotation range";
    serviceConfig = {
      ExecStart = "${pkgs.ndppd}/bin/ndppd -c /run/searxng/ndppd.conf";
      Restart = "on-failure";
    };
  };
}
