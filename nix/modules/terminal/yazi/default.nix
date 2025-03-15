{ config, lib, pkgs, catppuccin ... }:

let
  cfg = config.modules.terminal.wezterm;
in {
  options.modules.terminal.wezterm = {
    enable = lib.mkEnableOption "Yazi configuration";
  };

  config = lib.mkIf cfg.enable {
    programs.yazi = {
      enable = true;
    };
    catppuccin.yazi = {
      enable = true;
      accent = "blue";
    };
  };
}
