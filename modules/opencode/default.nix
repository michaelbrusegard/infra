{ config, lib, pkgs-unstable-updated, ... }:

let
  cfg = config.modules.opencode;
in {
  options.modules.opencode.enable = lib.mkEnableOption "OpenCode Configuration";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs-unstable-updated; [
      opencode
    ];
    xdg.configFile."opencode".source = ./config;
  };
}
