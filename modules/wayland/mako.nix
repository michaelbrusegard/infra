{ config, lib, ... }:

let
  cfg = config.modules.wayland;
in {
  config = lib.mkIf cfg.enable {
    services.mako = {
      enable = true;
      borderRadius = 3;
      borderSize = 1;
      defaultTimeout = 5000;
      width = 400;
      height = 100;
      font = "SF Pro 11";
      margin = "16";
      padding = "15";
      backgroundColor = "#1e2021ee";
      textColor = "#ffffff";
      borderColor = "#a0c4e2";
      progressColor = "over #a0c4e2";
      layer = "overlay";
      icons = true;
      maxIconSize = 48;
      iconPath = "/usr/share/icons/Papirus-Dark";
    };
  };
}
