{ config, lib, pkgs, ... }:

let
  cfg = config.modules.terminal.wezterm;
in {
  options.modules.terminal.wezterm = {
    enable = lib.mkEnableOption "WezTerm configuration";
  };

  config = lib.mkIf cfg.enable {
    programs.wezterm = {
      enable = true;
      enableZshIntegration = true;
    };

    xdg.configFile."wezterm" = {
      source = ./config;
      recursive = true;
    };
  };
}
