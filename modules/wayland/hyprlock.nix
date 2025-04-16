{ config, lib, ... }:

let
  cfg = config.modules.wayland;
in {
  config = lib.mkIf cfg.enable {
    programs.hyprlock = {
      enable = true;
      settings = {
        general = {
          ignore_empty_input = true;
          grace = 0;
          disable_loading_bar = true;
        };
        background = [
          {
            path = "${config.home.homeDirectory}/Developer/dotfiles/assets/wallpapers/twilight-peaks.png";
          }
        ];
        label = [
          {
            text = "cmd[update:1000] LC_TIME=en_GB.UTF-8 date '+%A %d %B'";
            color = "rgba(255,255,255,0.8)";
            font_size = 24;
            font_family = "SF Pro";
            position = "0,580";
            halign = "center";
            valign = "center";
          }
          {
            text = "cmd[update:1000] date '+%H:%M'";
            color = "rgba(255,255,255,0.8)";
            font_size = 96;
            font_family = "SF Pro";
            position = "0,500";
            halign = "center";
            valign = "center";
          }
        ];
        input-field = [
          {
            size = "160,40";
            outline_thickness = 0;
            dots_size = 0.2;
            dots_center = false;
            outer_color = "rgba(0,0,0,0)";
            inner_color = "rgba(78,78,78,0.8)";
            font_color = "rgba(222,222,222,1)";
            font_family = "SF Pro";
            placeholder_text = "Enter Password";
            fade_on_empty = false;
            position = "0,-580";
            halign = "center";
            valign = "center";
          }
        ];
      };
    };
  };
}
