{
  pkgs,
  config,
  lib,
  isWsl,
  homePersistenceRoot ? null,
  paseoHostnames,
  ...
}: let
  # Every directory under config/skills is a skill.
  skills =
    lib.mapAttrs (name: _: "${../../config/skills + "/${name}"}")
    (lib.filterAttrs (_: type: type == "directory") (builtins.readDir ../../config/skills));
  agentInstructions = ../../config/AGENTS.md;
  skillFilesFor = directory:
    lib.mapAttrs' (name: source:
      lib.nameValuePair "${directory}/${name}" {
        inherit source;
        recursive = true;
      })
    skills;
  # All skills are directories, and Codex needs directory symlinks rather than
  # individually symlinked files.
  codexSkillFiles = lib.mapAttrs (_: file: file // {recursive = false;}) (skillFilesFor (
    if config.home.preferXdgDirectories
    then "${config.xdg.configHome}/codex/skills"
    else ".codex/skills"
  ));
  claudeSkillFiles = skillFilesFor "${config.programs.claude-code.configDir}/skills";
  piSkillFiles = skillFilesFor ".pi/agent/skills";
  # OpenCode registers <config dir>/skill as a skill source, singular.
  opencodeSkillFiles = skillFilesFor "${config.xdg.configHome}/opencode/skill";
  cliproxy = {
    baseUrl = "https://ai.asgard.michaelbrusegard.com";
    # A non-secret placeholder: NetBird authenticates the device and injects
    # the upstream credential. GUI apps must not depend on shell exports.
    apiKey = "netbird";
  };
  # Route Pi's built-in providers through the gateway, keeping their catalogs.
  piModels.providers =
    lib.mapAttrs (_: baseUrl: {
      inherit baseUrl;
      inherit (cliproxy) apiKey;
    }) {
      anthropic = cliproxy.baseUrl;
      openai = "${cliproxy.baseUrl}/v1";
      moonshotai = "${cliproxy.baseUrl}/v1";
    };
  direnvWrapped = package: executable:
    (pkgs.writeShellApplication {
      name = executable;
      runtimeInputs = [pkgs.direnv];
      text = ''
        exec direnv exec "$PWD" ${lib.getExe package} "$@"
      '';
    }).overrideAttrs (_: {
      inherit (package) version;
    });
  # Desktop apps own their localhost servers; expose only their default ports
  # on NetBird without starting a second daemon or exposing LAN interfaces.
  agentUiPorts = {
    paseo = 6767;
    t3code = 3773;
  };
  netbirdForwarders = lib.mapAttrs (name: port:
    pkgs.writeShellApplication {
      name = "${name}-netbird-forward";
      runtimeInputs =
        [
          pkgs.gawk
          pkgs.nmap
        ]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          pkgs.iproute2
        ];
      text = ''
        # Give the background listener its own process group so its connection
        # workers cannot retain the listening socket after a restart.
        set -m

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
          if [ -n "$forward_pid" ]; then
            kill -- "-$forward_pid" 2>/dev/null || true
            wait "$forward_pid" 2>/dev/null || true
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

          echo "Forwarding $netbird_ip:${toString port} to 127.0.0.1:${toString port}"
          ncat -4 --listen --keep-open "$netbird_ip" ${toString port} \
            --sh-exec "ncat -4 127.0.0.1 ${toString port}" &
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
          sleep 5
        done
      '';
    })
  agentUiPorts;
in {
  programs = {
    # T3 and Loc create fresh worktrees for threads; trust their project
    # environments so the direnv-wrapped agents can start inside them.
    direnv.config.whitelist.prefix = lib.optionals (!isWsl) (
      [
        "${config.home.homeDirectory}/.t3/worktrees"
        "${config.home.homeDirectory}/.local/share/loc"
      ]
      # Loc keeps its thread worktrees in Application Support on macOS.
      ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
        "${config.home.homeDirectory}/Library/Application Support/loc/workspaces"
      ]
    );

    # Defaults live in /etc/codex/config.toml (modules/common/codex.nix), so
    # Codex keeps ~/.codex/config.toml for project trust and TUI state.
    codex = {
      enable = true;
      package = direnvWrapped pkgs.codex "codex";
    };

    opencode = {
      enable = true;
      package = direnvWrapped pkgs.opencode "opencode";
      # The module writes this straight to the config dir as AGENTS.md.
      context = agentInstructions;
      settings = {
        permission = "allow";
        # Native providers inherit new models and capabilities from models.dev.
        # Disable the OAuth plugins that can replace the configured gateway.
        plugins = ["-opencode.provider.openai" "-opencode.provider.chatgpt"];
        enabled_providers = ["openai" "anthropic" "moonshotai"];
        providers = lib.mapAttrs (_: provider:
          provider
          // {
            settings = {
              baseURL = "${cliproxy.baseUrl}/v1";
              inherit (cliproxy) apiKey;
              transport = "http";
            };
          }) {
          openai = {
            name = "Asgard / OpenAI";
          };
          anthropic = {
            name = "Asgard / Claude";
          };
          moonshotai = {
            name = "Asgard / Kimi";
          };
        };
      };
    };

    claude-code = {
      enable = true;
      package = direnvWrapped pkgs.claude-code "claude";
      settings = {
        model = "claude-opus-5-5";
        effortLevel = "high";
        env = {
          ANTHROPIC_BASE_URL = cliproxy.baseUrl;
          ANTHROPIC_AUTH_TOKEN = cliproxy.apiKey;
          CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = "1";
        };
        autoMemoryEnabled = false;
        disableRemoteControl = true;
        enableAllProjectMcpServers = true;
        enableArtifact = false;
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
          (direnvWrapped pkgs.pi-coding-agent "pi")
          pkgs.slack-cli
        ]
        ++ lib.optionals (!isWsl) (
          with pkgs; [
            paseo
            paseo-desktop
            (t3code-nightly.override {
              # Preserve project environments instead of using unwrapped providers.
              claude-code = config.programs.claude-code.package;
              codex = config.programs.codex.package;
              opencode = config.programs.opencode.package;
              pi-coding-agent = direnvWrapped pkgs.pi-coding-agent "pi";
              gh = config.programs.gh.package;
              backendPort = agentUiPorts.t3code;
            })
            chatgpt
          ]
        );

      file =
        {
          ".codex/AGENTS.md".source = agentInstructions;
          ".claude/CLAUDE.md".source = agentInstructions;
          # Claude writes this file itself, so replace its mutable copy when
          # returning the settings to declarative management.
          "${config.home.homeDirectory}/.claude/settings.json".force = true;
          ".pi/agent/AGENTS.md".source = agentInstructions;
          ".pi/agent/models.json".text = builtins.toJSON piModels;
        }
        // codexSkillFiles
        // claudeSkillFiles
        // piSkillFiles
        // opencodeSkillFiles;

      activation.piConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
        config_file="$HOME/.pi/agent/settings.json"
        config_dir=$(dirname "$config_file")
        temp_file=$(mktemp)

        if [ -f "$config_file" ]; then
          ${lib.getExe pkgs.jq} \
            --arg npm ${lib.escapeShellArg (lib.getExe' pkgs.nodejs "npm")} '
            def package_source:
              if type == "string" then .
              elif type == "object" then (.source // "")
              else ""
              end;
            def is_cliproxy:
              package_source
              | test("^(npm:)?@router-for-me/pi-cliproxyapi-provider(@.*)?$|^/nix/store/[^/]+-pi-cliproxyapi-provider-[^/]+$");
            .npmCommand = [$npm]
            | .defaultProvider = "anthropic"
            | .defaultModel = "claude-opus-5-5"
            | .defaultThinkingLevel = "high"
            # Agent apps start Pi without a UI in fresh worktrees, where the
            # trust prompt cannot appear and repo skills would be skipped.
            | .defaultProjectTrust = "always"
            | .retry = ((.retry // {}) + {maxRetries: 6})
            # WebSocket handshakes have no model body for NetBird to authorize.
            | .transport = "sse"
            # The gateway now goes through models.json, not a provider package.
            | .packages = [(.packages // [])[] | select(is_cliproxy | not)]
          ' "$config_file" > "$temp_file"
        else
          ${lib.getExe pkgs.jq} -n \
            --arg npm ${lib.escapeShellArg (lib.getExe' pkgs.nodejs "npm")} '{
              npmCommand: [$npm],
              defaultProvider: "anthropic",
              defaultModel: "claude-opus-5-5",
              defaultThinkingLevel: "high",
              defaultProjectTrust: "always",
              retry: {maxRetries: 6},
              transport: "sse"
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
            --argjson hostnames '${builtins.toJSON paseoHostnames}' '
            .daemon = ((.daemon // {}) + {
              hostnames: (((.daemon.hostnames // []) + $hostnames) | unique)
            })
          ' "$config_file" > "$temp_file"
        else
          ${lib.getExe pkgs.jq} \
            --argjson hostnames '${builtins.toJSON paseoHostnames}' \
            '{
              version: 1,
              daemon: {
                hostnames: $hostnames
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
            # V2 also writes cli.json and service credentials in the config
            # directory alongside Home Manager's declarative files.
            ".config/opencode"
            ".local/share/opencode"
            ".local/state/opencode"
            ".cache/slack-cli"
          ]
          ++ lib.optionals (!isWsl) [
            ".config/Codex"
            ".config/Paseo"
            ".paseo"
            ".config/t3code"
            ".t3"
            ".local/share/loc"
            ".local/state/loc"
          ];
        files = [
          ".claude.json"
        ];
      };
    };

  launchd.agents = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (lib.mapAttrs' (name: forwarder:
    lib.nameValuePair "${name}-netbird-forward" {
      enable = true;
      config = {
        ProgramArguments = [(lib.getExe forwarder)];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/${name}-netbird-forward.log";
        StandardErrorPath = "/tmp/${name}-netbird-forward.log";
      };
    })
  netbirdForwarders);

  systemd.user.services = lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && !isWsl) (lib.mapAttrs' (name: forwarder:
    lib.nameValuePair "${name}-netbird-forward" {
      Unit = {
        Description = "Expose ${name} localhost server on NetBird";
        After = ["network-online.target"];
      };
      Service = {
        ExecStart = "${lib.getExe forwarder}";
        Restart = "always";
        RestartSec = 5;
      };
      Install.WantedBy = ["default.target"];
    })
  netbirdForwarders);
}
