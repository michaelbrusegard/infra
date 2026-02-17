_: {
  imports = [
    ./spec
    ./options.nix
    ./keys.nix
    ./ui.nix
    ./util.nix
  ];

  config.programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
  };
}
