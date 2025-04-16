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
      backgroundColor = "#1e1e1edd";
      textColor = "#ffffff";
      borderColor = "#7e7e7e";
      layer = "overlay";
    };
  };
}
