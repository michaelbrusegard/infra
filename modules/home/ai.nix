{
  inputs,
  pkgs,
  lib,
  isWsl,
  homePersistenceRoot ? null,
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
      while true; do
        if command -v ip >/dev/null 2>&1; then
          netbird_ip=$(ip -o -4 addr show scope global | awk '
            $4 ~ /^100\./ { split($4, parts, "/"); print parts[1]; exit }
          ')
        else
          netbird_ip=$(/sbin/ifconfig | awk '
            /^utun[0-9]+:/ { iface = $1; sub(":", "", iface) }
            iface != "" && $1 == "inet" && $2 ~ /^100\./ { print $2; exit }
          ')
        fi

        if [ -n "$netbird_ip" ]; then
          break
        fi

        sleep 5
      done

      exec ncat -4 --listen --keep-open "$netbird_ip" 6767 \
        --sh-exec "ncat -4 127.0.0.1 6767"
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
