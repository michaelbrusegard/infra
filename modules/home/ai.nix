{
  pkgs,
  lib,
  isWsl,
  homePersistenceRoot ? null,
  paseoHostnames,
  ...
}: let
  openBrowserUseVersion = "0.1.41";
  openBrowserUseSource = pkgs.fetchFromGitHub {
    owner = "iFurySt";
    repo = "open-browser-use";
    rev = "v${openBrowserUseVersion}";
    hash = "sha256-126y3P32bqa0tH1+3l/HfZbxItrKOCA/S66AFjueivs=";
  };
  openBrowserUseSkill = "${openBrowserUseSource}/skills/open-browser-use";
  openBrowserUseCommand = lib.getExe pkgs.open-browser-use;
  openComputerUseSource = pkgs.fetchFromGitHub {
    owner = "iFurySt";
    repo = "open-codex-computer-use";
    rev = "v0.3.1";
    hash = "sha256-e3JUiCNFl5nCQph4exBf+BH/6UdRgVTwUJzZE/eGY2s=";
  };
  openComputerUseSkill = "${openComputerUseSource}/skills/open-computer-use";
  openComputerUseCommand = lib.getExe pkgs.open-computer-use;
  direnvWrapped = package: executable:
    (pkgs.writeShellApplication {
      name = executable;
      runtimeInputs = [pkgs.direnv];
      text = ''
        exec direnv exec "$PWD" ${lib.getExe' package executable} "$@"
      '';
    }).overrideAttrs (_: {
      inherit (package) version;
    });
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
  programs = {
    codex = {
      enable = true;
      package = direnvWrapped pkgs.codex "codex";
      settings = {
        approval_policy = "never";
        sandbox_mode = "danger-full-access";
        apps._default.enabled = false;
        mcp_servers = {
          open_browser_use = {
            command = openBrowserUseCommand;
            args = ["mcp"];
            default_tools_approval_mode = "approve";
          };
          open_computer_use = {
            command = openComputerUseCommand;
            args = ["mcp"];
            default_tools_approval_mode = "approve";
          };
        };
      };
      skills.open-browser-use = openBrowserUseSkill;
      skills.open-computer-use = openComputerUseSkill;
    };

    claude-code = {
      enable = true;
      package = direnvWrapped pkgs.claude-code "claude";
      mcpServers = {
        open-browser-use = {
          type = "stdio";
          command = openBrowserUseCommand;
          args = ["mcp"];
        };
        open-computer-use = {
          type = "stdio";
          command = openComputerUseCommand;
          args = ["mcp"];
        };
      };
      skills.open-browser-use = openBrowserUseSkill;
      skills.open-computer-use = openComputerUseSkill;
      settings = {
        disableRemoteControl = true;
        enableAllProjectMcpServers = true;
        enableArtifact = false;
        env.ENABLE_CLAUDEAI_MCP_SERVERS = "false";
        permissions.defaultMode = "bypassPermissions";
        sandbox.enabled = false;
        skipDangerousModePermissionPrompt = true;
        attribution = {
          commit = "";
          pr = "";
          sessionUrl = false;
        };
      };
    };
  };

  home =
    {
      packages =
        [
          (direnvWrapped pkgs.omp "omp")
          pkgs.open-browser-use
          pkgs.open-computer-use
        ]
        ++ lib.optionals (!isWsl) (with pkgs;
          [
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

      file = {
        ".omp/agent/config.yml".source = (pkgs.formats.yaml {}).generate "omp-config.yml" {
          disabledProviders = [
            "claude"
            "codex"
          ];
          tools.approvalMode = "yolo";
        };
        ".omp/agent/mcp.json".text = builtins.toJSON {
          "$schema" = "https://raw.githubusercontent.com/can1357/oh-my-pi/main/packages/coding-agent/src/config/mcp-schema.json";
          mcpServers = {
            open-browser-use = {
              type = "stdio";
              command = openBrowserUseCommand;
              args = ["mcp"];
            };
            open-computer-use = {
              type = "stdio";
              command = openComputerUseCommand;
              args = ["mcp"];
            };
          };
        };
        ".omp/agent/skills/open-browser-use" = {
          source = openBrowserUseSkill;
          recursive = true;
        };
        ".omp/agent/skills/open-computer-use" = {
          source = openComputerUseSkill;
          recursive = true;
        };
        "Library/Application Support/Open Browser Use/Chrome Extension" = lib.mkIf pkgs.stdenv.isDarwin {
          source = pkgs.open-browser-use.chromeExtensionUnpacked;
          recursive = true;
        };
      };

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
            ".omp"
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

  programs.chromium = lib.mkIf (!isWsl) {
    enable = true;
    package =
      if pkgs.stdenv.isDarwin
      then pkgs.brewCasks.ungoogled-chromium
      else pkgs.ungoogled-chromium;
    extensions = lib.optionals pkgs.stdenv.isLinux [
      {
        id = "bgjoihaepiejlfjinojjfgokghnodnhd";
        crxPath = pkgs.open-browser-use.chromeExtension;
        version = openBrowserUseVersion;
      }
    ];
    nativeMessagingHosts = [pkgs.open-browser-use];
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
