{ pkgs, ... }: {
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
  };
  xdg.configFile."wezterm" = {
    source = ./config;
    recursive = true;
  };
};
