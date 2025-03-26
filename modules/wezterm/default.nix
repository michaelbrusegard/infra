{ config, lib, ... }:

let
  cfg = config.modules.wezterm;
in {
  options.modules.wezterm.enable = lib.mkEnableOption "WezTerm configuration";

  config = lib.mkIf cfg.enable {
    programs.wezterm = {
      enable = true;
      enableZshIntegration = true;
    };
    xdg.configFile."wezterm".source = ./config;
  };
}
