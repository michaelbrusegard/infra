{
  inputs,
  pkgs,
  lib,
  homePersistenceRoot ? null,
  ...
}: {
  disabledModules = ["${inputs.home-manager}/modules/programs/opencode.nix"];
  imports = [
    "${inputs.home-manager-unstable}/modules/programs/opencode.nix"
  ];

  programs.opencode = {
    enable = true;
    settings = {
      autoupdate = false;
      plugin = ["oh-my-openagent" "@simonwjackson/opencode-direnv"];
    };
    tui.theme = "catppuccin";
    context = ''
      Always use caveman mode for responses.
    '';
    skills = {
      frontend-design = "${inputs.claude-code-skills}/plugins/frontend-design/skills/frontend-design";
      caveman = "${inputs.caveman-skills}/skills/caveman";
    };
  };
  xdg.configFile."opencode/oh-my-opencode.json".text = builtins.toJSON {
    git_master = {
      commit_footer = false;
      include_co_authored_by = false;
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
        ".local/share/opencode"
        ".omo"
      ];
    };
}
