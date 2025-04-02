{ config, lib, ... }:

let
  cfg = config.modules.wayland;
in {
  config = lib.mkIf cfg.enable {
    services.hyprpaper = {
      enable = true;
      settings = {
        preload = "/home/${config.home.username}/Developer/dotfiles/assets/wallpapers/twillight-peaks.png";
        wallpaper = "*,/home/${config.home.username}/Developer/dotfiles/assets/wallpapers/twillight-peaks.png";
      };
    };
  };
}
