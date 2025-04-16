{ config, lib, ... }:

let
  cfg = config.modules.wayland;
in {
  config = lib.mkIf cfg.enable {
    services.mako = {
      enable = true;
      borderRadius = 8;
      borderSize = 1;
      defaultTimeout = 5000;
      width = 360;
      height = 80;
      font = "SF Pro Nerd Font 12";
      margin = "16";
      padding = "16";
      backgroundColor = "rgba(36, 36, 36, 0.75)";
      textColor = "#fff";
      borderColor = "#7e7e7e";
      layer = "overlay";
      icons = true;
      maxIconSize = 48;
      iconPath = "/usr/share/icons/Papirus-Dark";
    };
  };
}
