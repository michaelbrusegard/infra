{ config, lib, userName, ... }:

let
  cfg = config.modules.wayland;
in {
  config = lib.mkIf cfg.enable {
    services.hyprpaper = {
      enable = true;
      settings = {
        preload = [ "/home/${userName}/Developer/dotfiles/assets/wallpapers/twilight-peaks.png" ];
        wallpaper = [ ",/home/${userName}/Developer/dotfiles/assets/wallpapers/twilight-peaks.png" ];
      };
    };
  };
}
