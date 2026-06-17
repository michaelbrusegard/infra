{
  inputs,
  pkgs,
  lib,
  homePersistenceRoot ? null,
  ...
}: {
  programs.opencode = {
    enable = true;
    settings.autoupdate = false;
    tui.theme = "catppuccin";
    skills = {
      frontend-design = "${inputs.claude-code-skills}/plugins/frontend-design/skills/frontend-design";
    };
  };
  home =
    {
      packages = with pkgs; [
        opencode-desktop
      ];
    }
    // lib.optionalAttrs (homePersistenceRoot != null) {
      persistence.${homePersistenceRoot}.directories = [
        ".config/opencode"
        ".config/ai.opencode.desktop"
        ".local/share/opencode"
      ];
    };
}
