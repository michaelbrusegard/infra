{ config, lib, pkgs, ... }:

let
  cfg = config.modules.wayland;
in {
  config = lib.mkIf cfg.enable {
    programs.waybar = {
      enable = true;
      systemd.enable = true;
      settings = {
        mainBar = {
          layer = "top";
          position = "top";
          height = 24;
          modules-left = [ "hyprland/window" ];
          modules-right = [ "hyprland/workspaces" "bluetooth" "network" "clock" ];
          "hyprland/window" = {
            separate-outputs = true;
          };
          "hyprland/workspaces" = {
            active-only = true;
          };
          "clock" = {
            format = "{:%d %b %H:%M}";
          };
        };
      };
      style = '''';
    };
    catppuccin.waybar = {
      enable = true;
      mode = "prependImport";
    };
  };
}
