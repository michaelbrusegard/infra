{ config, lib, ... }:

let
  cfg = config.modules.wayland;
in {
  config = lib.mkIf cfg.enable {
    services.mako = {
      enable = true;
      borderRadius = 8;
      defaultTimeout = 5000;
      width = 360;
      height = 80;
      font = "SF Pro Nerd Font 12";
      margin = "16";
      padding = "16";
      backgroundColor = "#1E1E1ECC";
      textColor = "#FFFFFF";
      borderColor = "#1E1E1E00";
      layer = "overlay";
      icons = true;
      maxIconSize = 48;
      iconPath = "/usr/share/icons/Papirus-Dark";
    };
  };
}
