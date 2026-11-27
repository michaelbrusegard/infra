{
  flake.modules.homeManager.ai =
    {
      pkgs,
      config,
      lib,
      isWsl,
      homePersistenceRoot ? null,
      ...
    }:
    let
      # Skill scripts such as babysit-pr's pr-wait use `#!/usr/bin/env python3`,
      # which NixOS cannot resolve outside a dev shell.
      skillsDir = pkgs.runCommand "agent-skills" { buildInputs = [ pkgs.python3 ]; } ''
        cp -r ${./skills} "$out"
        chmod -R u+w "$out"
        patchShebangs "$out"
      '';
      # Codex, Pi, and OpenCode read ~/.agents/skills; Claude Code reads only its
      # own directory. Link skills one by one to leave room for unmanaged ones,
      # and avoid the modules' skills options, which read the store at eval time.
      skillFilesIn =
        directory: recursive:
        lib.mapAttrs' (
          name: _:
          lib.nameValuePair "${directory}/${name}" {
            source = "${skillsDir}/${name}";
            inherit recursive;
          }
        ) (lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./skills));
      agentInstructions = ./instructions.md;
      cliproxy = {
        baseUrl = "https://ai.asgard.michaelbrusegard.com";
        # A non-secret placeholder: NetBird authenticates the device and injects
        # the upstream credential. GUI apps must not depend on shell exports.
        apiKey = "netbird";
      };
      # Pi 1.5.2's catalog predates GPT-6.2. These mirror its built-in OpenAI
      # GPT-6.1 Sol entry with OpenAI's published 6.2 prices; drop them once Pi
      # ships the models itself.
      piOpenAIGpt62 =
        {
          id,
          name,
          cost,
        }:
        {
          inherit id name cost;
          reasoning = true;
          input = [
            "text"
            "image"
          ];
          contextWindow = 272000;
          maxTokens = 128000;
          thinkingLevelMap = {
            off = null;
            minimal = null;
            low = "low";
            medium = "medium";
            high = "high";
            xhigh = "xhigh";
            max = "max";
          };
          compat = {
            supportsStrictMode = true;
            supportsOpenAIGrammarTools = true;
            supportsAdditionalTools = true;
            supportsToolSearch = true;
            supportsMidConvoSystemMessages = true;
            supportsExplicitPromptCacheMode = true;
            supportsMidConvoEffort = true;
          };
        };
      # Route Pi's built-in providers through the gateway, keeping their catalogs.
      piModels.providers =
        lib.recursiveUpdate
          (lib.mapAttrs
            (_: baseUrl: {
              inherit baseUrl;
              inherit (cliproxy) apiKey;
            })
            {
              anthropic = cliproxy.baseUrl;
              openai = "${cliproxy.baseUrl}/v1";
              moonshotai = "${cliproxy.baseUrl}/v1";
            }
          )
          {
            openai.models = [
              (piOpenAIGpt62 {
                id = "gpt-6.2-sol";
                name = "GPT-6.2 Sol";
                cost = {
                  input = 2;
                  output = 10;
                  cacheRead = 0.1;
                  cacheWrite = 2.5;
                  tiers = [
                    {
                      inputTokensAbove = 272000;
                      input = 4;
                      output = 15;
                      cacheRead = 0.2;
                      cacheWrite = 5;
                    }
                  ];
                };
              })
              (piOpenAIGpt62 {
                id = "gpt-6.2-astra";
                name = "GPT-6.2 Astra";
                cost = {
                  input = 8;
                  output = 40;
                  cacheRead = 0.4;
                  cacheWrite = 10;
                  tiers = [
                    {
                      inputTokensAbove = 272000;
                      input = 16;
                      output = 60;
                      cacheRead = 0.8;
                      cacheWrite = 20;
                    }
                  ];
                };
              })
            ];
          };
      # The gateway translates Anthropic Messages for its other models, but
      # Claude Code's discovery keeps only IDs containing "claude".
      claudeGatewayModels = [
        {
          model = "gpt-6.2-sol";
          label = "GPT-6.2 Sol";
        }
        {
          model = "gpt-6.1-terra";
          label = "GPT-6.1 Terra";
        }
        {
          model = "gpt-6-luna";
          label = "GPT-6 Luna";
        }
        {
          model = "gpt-6.2-astra";
          label = "GPT-6.2 Astra";
        }
        {
          model = "kimi-k3.1-pro";
          label = "Kimi K3.1 Pro";
        }
      ];
      # T3 only lists custom Claude models that declare capabilities, and passes
      # effort through only when the model offers it.
      t3ClaudeCustomModels = map (entry: {
        slug = entry.model;
        name = entry.label;
        capabilities.optionDescriptors = [
          {
            id = "effort";
            label = "Reasoning";
            type = "select";
            options = [
              {
                id = "low";
                label = "Low";
              }
              {
                id = "medium";
                label = "Medium";
              }
              {
                id = "high";
                label = "High";
                isDefault = true;
              }
              {
                id = "xhigh";
                label = "Extra High";
              }
              {
                id = "max";
                label = "Max";
              }
            ];
          }
        ];
      }) claudeGatewayModels;
      direnvWrapped =
        package: executable:
        (pkgs.writeShellApplication {
          name = executable;
          runtimeInputs = [ pkgs.direnv ];
          text = ''
            exec direnv exec "$PWD" ${lib.getExe package} "$@"
          '';
        }).overrideAttrs
          (_: {
            inherit (package) version;
          });
      # Desktop apps own their localhost servers; expose only their default ports
      # on NetBird without starting a second daemon or exposing LAN interfaces.
      agentUiPorts = {
        t3code = 3773;
      };
      netbirdCli =
        if pkgs.stdenv.hostPlatform.isDarwin then
          "/opt/homebrew/bin/netbird"
        else
          "/run/current-system/sw/bin/netbird";
      netbirdForwarders = lib.mapAttrs (
        name: port:
        pkgs.writeShellApplication {
          name = "${name}-netbird-forward";
          runtimeInputs = [
            pkgs.jq
            pkgs.nmap
          ];
          text = ''
            # Give the background listener its own process group so its connection
            # workers cannot retain the listening socket after a restart.
            set -m

            # Tailscale also hands out 100.64.0.0/10 addresses, so ask the daemon
            # rather than guessing from interface addresses. Use the system CLI:
            # NixOS's wrapper knows the client's socket path.
            get_netbird_ip() {
              ${netbirdCli} status --json 2>/dev/null \
                | jq -r '.netbirdIp // empty | split("/")[0] // empty' || true
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
        }
      ) agentUiPorts;
    in
    {
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

        # Defaults live in /etc/codex/config.toml (modules/features/codex.nix), so
        # Codex keeps ~/.codex/config.toml for project trust and TUI state.
        codex = {
          enable = true;
          package = direnvWrapped pkgs.codex "codex";
          context = agentInstructions;
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
            plugins = [
              "-opencode.provider.openai"
              "-opencode.provider.chatgpt"
            ];
            enabled_providers = [
              "openai"
              "anthropic"
              "moonshotai"
            ];
            providers =
              lib.mapAttrs
                (
                  _: provider:
                  provider
                  // {
                    settings = {
                      baseURL = "${cliproxy.baseUrl}/v1";
                      inherit (cliproxy) apiKey;
                      transport = "http";
                    };
                  }
                )
                {
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
          context = agentInstructions;
          settings = {
            model = "claude-opus-5-5";
            effortLevel = "high";
            env = {
              ANTHROPIC_BASE_URL = cliproxy.baseUrl;
              ANTHROPIC_AUTH_TOKEN = cliproxy.apiKey;
              CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = "1";
              # Claude Code otherwise drops effort for model IDs it doesn't know.
              CLAUDE_CODE_ALWAYS_ENABLE_EFFORT = "1";
              # Send Anthropic no metrics, error reports, surveys, or /feedback
              # transcripts, which are kept for up to 5 years. Nix handles updates.
              CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
            };
            modelPicker.options = claudeGatewayModels;
            # ClickHouse archives every session; local transcripts only serve resume.
            cleanupPeriodDays = 14;
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

      home = {
        packages = [
          (direnvWrapped pkgs.pi-coding-agent "pi")
          (direnvWrapped pkgs.antigravity-cli "agy")
          pkgs.slack-cli
        ]
        ++ lib.optionals (!isWsl) (
          with pkgs;
          [
            (t3code.override {
              # Preserve project environments instead of using unwrapped providers.
              claude-code = config.programs.claude-code.finalPackage;
              codex = config.programs.codex.package;
              opencode = config.programs.opencode.package;
              pi-coding-agent = direnvWrapped pkgs.pi-coding-agent "pi";
              gh = config.programs.gh.package;
              backendPort = agentUiPorts.t3code;
            })
          ]
        );

        # Opening the macOS app bundle skips the t3code wrapper, but T3 also reads
        # this telemetry opt-out from the login shell.
        sessionVariables = lib.mkIf (!isWsl) {
          T3CODE_TELEMETRY_ENABLED = "false";
        };

        file = {
          # Claude writes this file itself, so replace its mutable copy when
          # returning the settings to declarative management.
          "${config.home.homeDirectory}/.claude/settings.json".force = true;
          ".pi/agent/AGENTS.md".source = agentInstructions;
          ".pi/agent/models.json".text = builtins.toJSON piModels;
        }
        # Codex ignores symlinked SKILL.md files, so link whole directories.
        // skillFilesIn ".agents/skills" false
        // skillFilesIn "${config.programs.claude-code.configDir}/skills" true;

        activation.piConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
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

        # T3 owns its settings file, so replace only the gateway models and keep
        # any custom models added in the app.
        activation.t3codeConfig = lib.mkIf (!isWsl) (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            config_file="$HOME/.t3/userdata/settings.json"
            config_dir=$(dirname "$config_file")
            temp_file=$(mktemp)

            { [ -f "$config_file" ] && cat "$config_file" || echo '{}'; } | ${lib.getExe pkgs.jq} \
              --argjson models '${builtins.toJSON t3ClaudeCustomModels}' '
              ($models | map(.slug)) as $slugs
              | .providerInstances.claudeAgent = (
                  (.providerInstances.claudeAgent // {driver: "claudeAgent"})
                  | .config.customModels = (
                      [(.config.customModels // [])[]
                        | select((if type == "string" then . else .slug end) as $slug
                            | $slugs | index($slug) | not)]
                      + $models
                    )
                )
            ' > "$temp_file"

            if [ ! -f "$config_file" ] || ! cmp -s "$temp_file" "$config_file"; then
              $DRY_RUN_CMD mkdir -p "$config_dir"
              $DRY_RUN_CMD install -m 0600 "$temp_file" "$config_file"
            fi

            rm -f "$temp_file"
          ''
        );
      }
      // lib.optionalAttrs (homePersistenceRoot != null) {
        persistence.${homePersistenceRoot} = {
          directories = [
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
            ".config/t3code-v2"
            ".t3"
            ".local/share/loc"
            ".local/state/loc"
          ];
          files = [
            ".claude.json"
          ];
        };
      };

      launchd.agents = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
        lib.mapAttrs' (
          name: forwarder:
          lib.nameValuePair "${name}-netbird-forward" {
            enable = true;
            config = {
              ProgramArguments = [ (lib.getExe forwarder) ];
              RunAtLoad = true;
              KeepAlive = true;
              StandardOutPath = "/tmp/${name}-netbird-forward.log";
              StandardErrorPath = "/tmp/${name}-netbird-forward.log";
            };
          }
        ) netbirdForwarders
      );

      systemd.user.services = lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && !isWsl) (
        lib.mapAttrs' (
          name: forwarder:
          lib.nameValuePair "${name}-netbird-forward" {
            Unit = {
              Description = "Expose ${name} localhost server on NetBird";
              After = [ "network-online.target" ];
            };
            Service = {
              ExecStart = "${lib.getExe forwarder}";
              Restart = "always";
              RestartSec = 5;
            };
            Install.WantedBy = [ "default.target" ];
          }
        ) netbirdForwarders
      );
    };
}
