{
  inputs,
  pkgs,
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
    rules = ''
      Always use caveman mode for responses.
    '';
    skills = {
      frontend-design = "${inputs.claude-code-skills}/plugins/frontend-design/skills/frontend-design";
      caveman = "${inputs.caveman-skills}/skills/caveman";
    };
  };
  home.packages = with pkgs; [
    opencode-desktop
  ];
}
