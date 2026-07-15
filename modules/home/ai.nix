{
  inputs,
  pkgs,
  lib,
  isWsl,
  homePersistenceRoot ? null,
  paseoHostnames,
  ...
}: let
  direnvWrapped = package: executable:
    pkgs.writeShellApplication {
      name = executable;
      runtimeInputs = [pkgs.direnv];
      text = ''
        exec direnv exec "$PWD" ${lib.getExe' package executable} "$@"
      '';
    };
  paseoNetbirdForward = pkgs.writeShellApplication {
    name = "paseo-netbird-forward";
    runtimeInputs =
      [
        pkgs.gawk
        pkgs.nmap
      ]
      ++ lib.optionals pkgs.stdenv.isLinux [
        pkgs.iproute2
      ];
    text = ''
      get_netbird_ip() {
        if command -v ip >/dev/null 2>&1; then
          ip -o -4 addr show scope global | awk '
            $4 ~ /^100\./ { split($4, parts, "/"); print parts[1]; exit }
          '
        else
          /sbin/ifconfig | awk '
            /^utun[0-9]+:/ { iface = $1; sub(":", "", iface) }
            iface != "" && $1 == "inet" && $2 ~ /^100\./ { print $2; exit }
          '
        fi
      }

      forward_pid=""

      stop_forwarder() {
        if [ -n "$forward_pid" ] && kill -0 "$forward_pid" 2>/dev/null; then
          kill "$forward_pid"
          wait "$forward_pid" || true
        fi
        forward_pid=""
      }

      trap stop_forwarder EXIT
      trap 'exit 0' INT TERM

      while true; do
        netbird_ip=$(get_netbird_ip)

        if [ -z "$netbird_ip" ]; then
          sleep 5
          continue
        fi

        echo "Forwarding $netbird_ip:6767 to 127.0.0.1:6767"
        ncat -4 --listen --keep-open "$netbird_ip" 6767 \
          --sh-exec "ncat -4 127.0.0.1 6767" &
        forward_pid=$!

        while kill -0 "$forward_pid" 2>/dev/null; do
          sleep 5
          current_ip=$(get_netbird_ip)
          if [ "$current_ip" != "$netbird_ip" ]; then
            echo "NetBird address changed from $netbird_ip to ''${current_ip:-unavailable}"
            break
          fi
        done

        stop_forwarder
      done
    '';
  };
in {
  imports = [
    inputs.pi.homeManagerModules.default
  ];

  programs = {
    codex = {
      enable = true;
      package = direnvWrapped pkgs.codex "codex";
    };

    claude-code = {
      enable = true;
      package = direnvWrapped pkgs.claude-code "claude";
    };

    opencode = {
      enable = true;
      package = direnvWrapped pkgs.opencode "opencode";
      settings.autoupdate = false;
      tui.theme = "catppuccin";
      skills = {
        frontend-design = "${inputs.claude-code-skills}/plugins/frontend-design/skills/frontend-design";
      };
    };

    pi.coding-agent = {
      enable = true;
      package = direnvWrapped pkgs.pi-coding-agent "pi";
    };
  };

  home =
    {
      packages = lib.mkIf (!isWsl) (with pkgs;
        [
          opencode-desktop
          t3code
        ]
        ++ lib.optionals pkgs.stdenv.isLinux [
          paseo
          paseo-desktop
        ]
        ++ lib.optionals pkgs.stdenv.isDarwin [
          brewCasks.codex-app
          brewCasks.paseo
        ]);

      activation.paseoHostnames = lib.mkIf (paseoHostnames != []) (lib.hm.dag.entryAfter ["writeBoundary"] ''
        config_file="$HOME/.paseo/config.json"
        config_dir=$(dirname "$config_file")
        temp_file=$(mktemp)

        if [ -f "$config_file" ]; then
          ${lib.getExe pkgs.jq} --argjson hostnames '${builtins.toJSON paseoHostnames}' '
            .daemon = ((.daemon // {}) + {
              hostnames: (((.daemon.hostnames // []) + $hostnames) | unique)
            })
          ' "$config_file" > "$temp_file"
        else
          ${lib.getExe pkgs.jq} --argjson hostnames '${builtins.toJSON paseoHostnames}' \
            '{version: 1, daemon: {hostnames: $hostnames}}' > "$temp_file"
        fi

        if [ ! -f "$config_file" ] || ! cmp -s "$temp_file" "$config_file"; then
          $DRY_RUN_CMD mkdir -p "$config_dir"
          $DRY_RUN_CMD install -m 0600 "$temp_file" "$config_file"
        fi

        rm -f "$temp_file"
      '');
    }
    // lib.optionalAttrs (homePersistenceRoot != null) {
      persistence.${homePersistenceRoot} = {
        directories =
          [
            ".claude"
            ".codex"
            ".config/ai.opencode.desktop"
            ".config/opencode"
            ".local/share/opencode"
            ".pi"
          ]
          ++ lib.optionals (!isWsl) [
            ".config/Paseo"
            ".config/t3code"
            ".paseo"
            ".t3"
          ];
        files = [
          ".claude.json"
        ];
      };
    };

  launchd.agents.paseo-netbird-forward = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [
        "${lib.getExe paseoNetbirdForward}"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/paseo-netbird-forward.log";
      StandardErrorPath = "/tmp/paseo-netbird-forward.log";
    };
  };

  systemd.user.services.paseo-netbird-forward = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
    Unit = {
      Description = "Expose Paseo localhost daemon on NetBird";
      After = ["network-online.target"];
    };
    Service = {
      ExecStart = "${lib.getExe paseoNetbirdForward}";
      Restart = "always";
      RestartSec = 5;
    };
    Install.WantedBy = ["default.target"];
  };
}
