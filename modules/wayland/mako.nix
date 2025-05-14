{ config, lib, ... }:

let
  cfg = config.modules.wayland;
in {
  config = lib.mkIf cfg.enable {
    services.mako = {
      enable = true;
      settings = {
        border-radius = 8;
        border-size = 1;
        default-timeout = 5000;
        width = 360;
        height = 80;
        font = "SFPro Nerd Font 12";
        margin = "16";
        padding = "16";
        background-color = "#1e1e1edd";
        text-color = "#ffffff";
        border-color = "#7e7e7e";
        layer = "overlay";
      };
    };
  };
}
