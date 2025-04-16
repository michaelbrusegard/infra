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
      font = "SF Pro 11";
      margin = "20";
      padding = "15";
      backgroundColor = "#1E1E1ECC";
      textColor = "#FFFFFF";
      borderColor = "#1E1E1E00";
      layer = "overlay";
    };
  };
}
