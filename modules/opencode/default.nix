{ config, lib, pkgs, ... }:

let
  cfg = config.modules.opencode;
in {
  options.modules.opencode.enable = lib.mkEnableOption "OpenCode Configuration";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      opencode
    ];
    xdg.configFile."opencode".source = "${config.home.homeDirectory}/Developer/dotfiles/modules/opencode/config";
  };
}
