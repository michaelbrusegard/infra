{
  pkgs,
  config,
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
  openBrowserUseExtensionDirectory =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "Library/Application Support/OpenBrowserUse/chrome-extension/release"
    else ".local/share/open-browser-use/chrome-extension/release";
  openComputerUseSource = pkgs.fetchFromGitHub {
    owner = "iFurySt";
    repo = "open-codex-computer-use";
    rev = "v0.3.1";
    hash = "sha256-e3JUiCNFl5nCQph4exBf+BH/6UdRgVTwUJzZE/eGY2s=";
  };
  openComputerUseSkill = "${openComputerUseSource}/skills/open-computer-use";
  openComputerUseCommand = lib.getExe pkgs.open-computer-use;
  skills = {
    babysit-pr = "${../../config/skills/babysit-pr}";
    blast-radius = "${../../config/skills/blast-radius}";
    diagnose = "${../../config/skills/diagnose}";
    domain-context = "${../../config/skills/domain-context}";
    excalidraw-diagram = "${../../config/skills/excalidraw-diagram}";
    file-pr = "${../../config/skills/file-pr}";
    frontend-design = "${../../config/skills/frontend-design}";
    grill = "${../../config/skills/grill}";
    incident-brief = "${../../config/skills/incident-brief}";
    open-browser-use = openBrowserUseSkill;
    open-computer-use = openComputerUseSkill;
    recall-work = "${../../config/skills/recall-work}";
    reflect-workflow = "${../../config/skills/reflect-workflow}";
    review-pr = "${../../config/skills/review-pr}";
    self-review = "${../../config/skills/self-review}";
    show-work = "${../../config/skills/show-work}";
    slack = "${../../config/skills/slack}";
    unslop = "${../../config/skills/unslop}";
    wizard = "${../../config/skills/wizard}";
    write-agent-instructions = "${../../config/skills/write-agent-instructions}";
  };
  agentInstructions = ../../config/AGENTS.md;
  paseoAgentInstructions = ''
    Prefer Paseo tools for agent delegation, workspace lifecycle, heartbeats,
    schedules, and Paseo browser tabs. Use Paseo's create_agent instead of a
    provider-native subagent when both can perform the task. A created agent must
    use the same Paseo provider as its parent; the model may differ, but the
    provider must not. Before delegating, call list_profiles and consider only
    profiles matching the current provider. Follow the selected profile's notes,
    and use provider discovery only when no matching profile fits. Use the paseo
    CLI only when an equivalent Paseo tool is unavailable. Keep direct coding
    work in the current workspace on the harness's local file and shell tools.
  '';
  piSkillFiles = lib.mapAttrs' (name: source:
    lib.nameValuePair ".pi/agent/skills/${name}" {
      inherit source;
      recursive = true;
    })
  skills;
  cliProxyApi = {
    baseUrl = "https://llm.asgard.michaelbrusegard.com";
    piProviderPackage = "npm:@router-for-me/pi-cliproxyapi-provider@1.4.13";
  };
  cliProxyApiKey = pkgs.writeShellApplication {
    name = "cliproxyapi-api-key";
    text = ''
      api_key_file=${lib.escapeShellArg config.secrets.keys.cliProxyApiKeyFile}

      if [ ! -r "$api_key_file" ]; then
        echo "CLIProxyAPI API key is unavailable at $api_key_file" >&2
        exit 1
      fi

      exec ${lib.getExe' pkgs.uutils-coreutils "uutils-cat"} "$api_key_file"
    '';
  };
  piCliProxyApi =
    (pkgs.writeShellApplication {
      name = "pi";
      runtimeInputs = [pkgs.nodejs];
      text = ''
        cli_proxy_api_key="$(${lib.getExe cliProxyApiKey})"
        export CLIPROXYAPI_API_KEY="$cli_proxy_api_key"
        export CLIPROXYAPI_BASE_URL=${lib.escapeShellArg cliProxyApi.baseUrl}

        exec ${lib.getExe pkgs.pi-coding-agent} "$@"
      '';
    }).overrideAttrs (_: {
      inherit (pkgs.pi-coding-agent) version;
    });
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
      ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
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
        model_provider = "cliproxyapi";
        model_providers.cliproxyapi = {
          name = "CLIProxyAPI";
          base_url = "${cliProxyApi.baseUrl}/v1";
          wire_api = "responses";
          auth.command = lib.getExe cliProxyApiKey;
        };
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
      inherit skills;
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
      inherit skills;
      settings = {
        apiKeyHelper = lib.getExe cliProxyApiKey;
        disableRemoteControl = true;
        enableAllProjectMcpServers = true;
        enableArtifact = false;
        env = {
          ANTHROPIC_BASE_URL = cliProxyApi.baseUrl;
          CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = "1";
          ENABLE_CLAUDEAI_MCP_SERVERS = "false";
        };
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
          (direnvWrapped piCliProxyApi "pi")
          pkgs.open-browser-use
          pkgs.open-computer-use
          pkgs.slack-cli
        ]
        ++ lib.optionals (!isWsl) (with pkgs;
          [
            paseo
            paseo-desktop
          ]
          ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
            brewCasks.codex-app
          ]);

      file =
        {
          ".codex/AGENTS.md".source = agentInstructions;
          ".claude/CLAUDE.md".source = agentInstructions;
          ".pi/agent/AGENTS.md".source = agentInstructions;
          "${openBrowserUseExtensionDirectory}" = lib.mkIf (!isWsl) {
            source = pkgs.open-browser-use.chromeExtensionUnpacked;
            recursive = true;
            force = true;
          };
        }
        // piSkillFiles;

      activation.piConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
        config_file="$HOME/.pi/agent/settings.json"
        config_dir=$(dirname "$config_file")
        temp_file=$(mktemp)

        if [ -f "$config_file" ]; then
          ${lib.getExe pkgs.jq} \
            --arg npm ${lib.escapeShellArg (lib.getExe' pkgs.nodejs "npm")} \
            --arg provider_package ${lib.escapeShellArg cliProxyApi.piProviderPackage} '
            def package_source:
              if type == "string" then .
              elif type == "object" then (.source // "")
              else ""
              end;
            def is_cliproxyapi:
              package_source
              | test("^(npm:)?@router-for-me/pi-cliproxyapi-provider(@.*)?$");
            def is_pi_loop:
              package_source
              | test("^(npm:)?@koltmcbride/pi-loop(@.*)?$");
            .npmCommand = [$npm]
            | .packages = (
                [(.packages // [])[] | select((is_cliproxyapi or is_pi_loop) | not)]
                + [$provider_package]
              )
          ' "$config_file" > "$temp_file"
        else
          ${lib.getExe pkgs.jq} -n \
            --arg npm ${lib.escapeShellArg (lib.getExe' pkgs.nodejs "npm")} \
            --arg provider_package ${lib.escapeShellArg cliProxyApi.piProviderPackage} '{
              npmCommand: [$npm],
              packages: [$provider_package]
            }' > "$temp_file"
        fi

        if [ ! -f "$config_file" ] || ! cmp -s "$temp_file" "$config_file"; then
          $DRY_RUN_CMD mkdir -p "$config_dir"
          $DRY_RUN_CMD install -m 0600 "$temp_file" "$config_file"
        fi

        rm -f "$temp_file"
      '';

      activation.paseoConfig = lib.mkIf (paseoHostnames != []) (lib.hm.dag.entryAfter ["writeBoundary"] ''
        config_file="$HOME/.paseo/config.json"
        config_dir=$(dirname "$config_file")
        temp_file=$(mktemp)

        if [ -f "$config_file" ]; then
          ${lib.getExe pkgs.jq} \
            --argjson hostnames '${builtins.toJSON paseoHostnames}' \
            --arg append_system_prompt ${lib.escapeShellArg paseoAgentInstructions} '
            .daemon = ((.daemon // {}) + {
              hostnames: (((.daemon.hostnames // []) + $hostnames) | unique),
              mcp: ((.daemon.mcp // {}) + {
                enabled: true,
                injectIntoAgents: true
              }),
              appendSystemPrompt: $append_system_prompt
            })
            | del(.agents.providers.kimi)
            | if .agents.providers? == {} then del(.agents.providers) else . end
            | if .agents? == {} then del(.agents) else . end
          ' "$config_file" > "$temp_file"
        else
          ${lib.getExe pkgs.jq} \
            --argjson hostnames '${builtins.toJSON paseoHostnames}' \
            --arg append_system_prompt ${lib.escapeShellArg paseoAgentInstructions} \
            '{
              version: 1,
              daemon: {
                hostnames: $hostnames,
                mcp: {
                  enabled: true,
                  injectIntoAgents: true
                },
                appendSystemPrompt: $append_system_prompt
              }
            }' > "$temp_file"
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
            ".pi"
            ".cache/slack-cli"
          ]
          ++ lib.optionals (!isWsl) [
            ".config/Paseo"
            ".paseo"
          ];
        files = [
          ".claude.json"
        ];
      };
    };

  programs.chromium = lib.mkIf (!isWsl) {
    enable = true;
    package =
      if pkgs.stdenv.hostPlatform.isDarwin
      then pkgs.brewCasks.ungoogled-chromium
      else pkgs.ungoogled-chromium;
    nativeMessagingHosts = [pkgs.open-browser-use];
  };

  launchd.agents.paseo-netbird-forward = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
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

  systemd.user.services.paseo-netbird-forward = lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && !isWsl) {
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
