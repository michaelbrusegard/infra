{
  pkgs,
  config,
  lib,
  isWsl,
  homePersistenceRoot ? null,
  paseoHostnames,
  ...
}: let
  skills = {
    babysit-pr = "${../../config/skills/babysit-pr}";
    blast-radius = "${../../config/skills/blast-radius}";
    diagnose = "${../../config/skills/diagnose}";
    domain-context = "${../../config/skills/domain-context}";
    excalidraw-diagram = "${../../config/skills/excalidraw-diagram}";
    file-pr = "${../../config/skills/file-pr}";
    frontend-design = "${../../config/skills/frontend-design}";
    grill = "${../../config/skills/grill}";
    recall-work = "${../../config/skills/recall-work}";
    review-pr = "${../../config/skills/review-pr}";
    self-review = "${../../config/skills/self-review}";
    slack = "${../../config/skills/slack}";
    unslop = "${../../config/skills/unslop}";
    write-agent-instructions = "${../../config/skills/write-agent-instructions}";
  };
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
  cliProxyApi = {
    baseUrl = "https://ai.asgard.michaelbrusegard.com";
    # A non-secret placeholder: NetBird authenticates the device and injects
    # the upstream credential. GUI apps must not depend on shell exports.
    apiKey = "netbird";
    piProviderPackage = "${pkgs.pi-cliproxyapi-provider}";
  };
  codexSettings = {
    model_provider = "cliproxyapi";
    model_providers.cliproxyapi = {
      name = "Asgard";
      base_url = "${cliProxyApi.baseUrl}/v1";
      model_catalog_url = "${cliProxyApi.baseUrl}/v1/models";
      # The placeholder enables API-key discovery without shell credentials.
      experimental_bearer_token = cliProxyApi.apiKey;
      wire_api = "responses";
      requires_openai_auth = false;
      supports_websockets = false;
    };
    apps._default.enabled = false;
    features.api_key_model_discovery = true;
    features.memories = false;
    memories = {
      generate_memories = false;
      use_memories = false;
    };
  };
  codexConfig = (pkgs.formats.toml {}).generate "codex-config" codexSettings;
  codexConfigJson = (pkgs.formats.json {}).generate "codex-config.json" codexSettings;
  piCliProxyApi =
    (pkgs.writeShellApplication {
      name = "pi";
      runtimeInputs = [pkgs.nodejs];
      text = ''
        # Pi requires a nonempty key; NetBird authenticates the peer instead.
        export CLIPROXYAPI_API_KEY=${lib.escapeShellArg cliProxyApi.apiKey}
        export CLIPROXYAPI_BASE_URL=${lib.escapeShellArg cliProxyApi.baseUrl}
        export CLIPROXYAPI_RESPONSES_URL=${lib.escapeShellArg "${cliProxyApi.baseUrl}/v1/responses"}
        # WebSocket handshakes have no model body for NetBird to authorize.
        export CLIPROXYAPI_TRANSPORT=sse

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

    codex = {
      enable = true;
      package = direnvWrapped pkgs.codex "codex";
      # Codex persists project trust and other TUI settings here, so an
      # activation script maintains a writable config instead of a store link.
      settings = {};
    };

    opencode = {
      enable = true;
      package = direnvWrapped pkgs.opencode "opencode";
      # The module writes this straight to the config dir as AGENTS.md.
      context = agentInstructions;
      settings = {
        # Native providers inherit new models and capabilities from models.dev.
        # Disable the OAuth plugins that can replace the configured gateway.
        plugins = ["-opencode.provider.openai" "-opencode.provider.chatgpt"];
        enabled_providers = ["openai" "anthropic" "moonshotai"];
        providers = lib.mapAttrs (_: provider:
          provider
          // {
            settings = {
              baseURL = "${cliProxyApi.baseUrl}/v1";
              inherit (cliProxyApi) apiKey;
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
        env = {
          ANTHROPIC_BASE_URL = cliProxyApi.baseUrl;
          ANTHROPIC_AUTH_TOKEN = cliProxyApi.apiKey;
          CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = "1";
        };
        autoMemoryEnabled = false;
        disableRemoteControl = true;
        enableArtifact = false;
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
              pi-coding-agent = direnvWrapped piCliProxyApi "pi";
              gh = config.programs.gh.package;
            })
            (
              if stdenv.hostPlatform.isLinux
              then chatgpt-desktop
              else chatgpt
            )
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
        }
        // codexSkillFiles
        // claudeSkillFiles
        // piSkillFiles
        // opencodeSkillFiles;

      activation.codexConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
        config_file="$HOME/.codex/config.toml"
        config_dir=$(dirname "$config_file")
        migration_file="${config.xdg.stateHome}/infra/ai-defaults-v1"
        temp_file=$(mktemp)
        sanitized_file=$(mktemp)
        user_json=$(mktemp)
        merged_json=$(mktemp)

        if [ -f "$config_file" ]; then
          # Clear retired defaults once, including copies misplaced beneath
          # TOML tables by older activations. Later user choices remain local.
          retired_keys="model_provider"
          if [ ! -e "$migration_file" ]; then
            retired_keys="$retired_keys|model|approval_policy|sandbox_mode"
          fi
          ${lib.getExe pkgs.gnused} -E \
            "/^[[:space:]]*($retired_keys)[[:space:]]*=/d" \
            "$config_file" > "$sanitized_file"

          # TOML puts every root scalar ahead of the first table, and yq
          # honours neither half of that: its writer follows map order and
          # its merge does not hoist scalars, so managed keys were appended
          # after the last [projects.*] header and codex read them as that
          # project's settings. The sort meant to prevent it never ran
          # either, because TOML tables come back with an empty tag rather
          # than !!map. Order the document in jq, where `type` tells tables
          # apart and object key order is dependable, and leave yq to
          # convert between formats.
          ${lib.getExe pkgs.yq-go} -p=toml -o=json '.' \
            "$sanitized_file" > "$user_json"

          ${lib.getExe pkgs.jq} -s '
            ((.[0]
              | del(.model_provider)
              | del(.mcp_servers.open_browser_use, .mcp_servers.open_computer_use,
                    .mcp_servers."open-browser-use", .mcp_servers."open-computer-use")
              | del(.model_providers.cliproxyapi)) * .[1]) as $merged
            | ($merged | with_entries(select(.value | type != "object")))
              + ($merged | with_entries(select(.value | type == "object")))
          ' "$user_json" ${lib.escapeShellArg codexConfigJson} > "$merged_json"

          ${lib.getExe pkgs.yq-go} -p=json -o=toml '.' \
            "$merged_json" > "$temp_file"
        else
          ${lib.getExe' pkgs.uutils-coreutils "uutils-cp"} \
            ${lib.escapeShellArg codexConfig} \
            "$temp_file"
        fi

        if [ ! -f "$config_file" ] || ! cmp -s "$temp_file" "$config_file"; then
          $DRY_RUN_CMD mkdir -p "$config_dir"
          $DRY_RUN_CMD install -m 0600 "$temp_file" "$config_file"
        fi

        if [ ! -e "$migration_file" ]; then
          $DRY_RUN_CMD mkdir -p "$(dirname "$migration_file")"
          $DRY_RUN_CMD touch "$migration_file"
        fi

        rm -f "$temp_file" "$sanitized_file" "$user_json" "$merged_json"
      '';

      activation.removeDesktopAutomationMcp = lib.hm.dag.entryAfter ["writeBoundary"] ''
        for config_file in "$HOME/.pi/agent/mcp.json" "$HOME/.claude.json"; do
          if [ ! -f "$config_file" ]; then
            continue
          fi

          temp_file=$(mktemp)
          ${lib.getExe pkgs.jq} '
            del(.mcpServers."open-browser-use", .mcpServers."open-computer-use",
                .mcpServers.open_browser_use, .mcpServers.open_computer_use)
          ' "$config_file" > "$temp_file"

          if ! cmp -s "$temp_file" "$config_file"; then
            $DRY_RUN_CMD install -m 0600 "$temp_file" "$config_file"
          fi
          rm -f "$temp_file"
        done
      '';

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
              | test("^(npm:)?@router-for-me/pi-cliproxyapi-provider(@.*)?$|^/nix/store/[^/]+-pi-cliproxyapi-provider-[^/]+$");
            def is_pi_loop:
              package_source
              | test("^(npm:)?@koltmcbride/pi-loop(@.*)?$");
            .npmCommand = [$npm]
            | .defaultProvider = "cliproxyapi"
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
              defaultProvider: "cliproxyapi",
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
            --argjson hostnames '${builtins.toJSON paseoHostnames}' '
            .daemon = ((.daemon // {}) + {
              hostnames: (((.daemon.hostnames // []) + $hostnames) | unique)
            })
            | if ((.daemon.appendSystemPrompt // "")
                  | startswith("Prefer Paseo tools for agent delegation,"))
              then
                del(.daemon.appendSystemPrompt,
                    .daemon.mcp.enabled, .daemon.mcp.injectIntoAgents)
                | if .daemon.mcp == {} then del(.daemon.mcp) else . end
              else .
              end
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
