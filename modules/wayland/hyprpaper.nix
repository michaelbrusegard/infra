{ config, lib, ... }:

let
  cfg = config.modules.wayland;
in {
  config = lib.mkIf cfg.enable {
    services.hyprpaper = {
      enable = true;
      settings = {
        preload = [ "~/Developer/dotfiles/assets/wallpapers/twillight-peaks.png" ];
        wallpaper = [ ",~/Developer/dotfiles/assets/wallpapers/twillight-peaks.png" ];
      };
    };
  };
}
