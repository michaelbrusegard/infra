{ config, lib, ... }:

let
  cfg = config.modules.wayland;
in {
  config = lib.mkIf cfg.enable {
    services.hyprpaper = {
      enable = true;
      settings = {
        preload = [ "${config.home.homeDirectory}/Developer/dotfiles/assets/wallpapers/twilight-peaks.png" ];
        wallpaper = [ ",/${config.home.homeDirectory}/Developer/dotfiles/assets/wallpapers/twilight-peaks.png" ];
      };
    };
  };
}
