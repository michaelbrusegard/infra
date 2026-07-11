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
}
