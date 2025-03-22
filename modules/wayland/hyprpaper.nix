{ config, lib, ... }:

let
  cfg = config.modules.wayland;
in {
  config = lib.mkIf cfg.enable {
    services.hyprpaper = {
      enable = true;
      settings = {
        preload = "../../assets/Twillight Peaks.png";
        wallpaper = ",../../assets/Twillight Peaks.png";
      },
    };
  };
}
