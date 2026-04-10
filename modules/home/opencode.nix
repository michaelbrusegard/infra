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
      plugin = ["oh-my-opencode" "@simonwjackson/opencode-direnv"];
    };
    tui.theme = "catppuccin";
  };
  home.packages = with pkgs; [
    opencode-desktop
  ];
}
