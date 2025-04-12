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
          grace = 300;
          disable_loading_bar = true;
        };
        background = [
          {
            path = "../../assets/twilight-peaks.png";
          }
        ];
        label = [
          {
            text = "cmd[update:1000] date '+%A %d %B'";
            color = "rgba(255, 255, 255, 0.8)";
            font_size = 24;
            font_family = "SF Pro";
            position =  [0 -220];
            halign = "center";
            valign = "center";
          }
          {
            text = "cmd[update:1000] date '+%H:%M'";
            color = "rgba(255, 255, 255, 1.0)";
            font_size = 96;
            font_family = "SF Pro";
            position =  [0 -140];
            halign = "center";
            valign = "center";
          }
        ];
        input-field = [
          {
            size = ["20%" "5%"];
            outline_thickness = 2;
            dots_size = 0.33;
            dots_spacing = 0.15;
            dots_center = true;
            dots_rounding = -1;
            outer_color = "rgba(100, 100, 100, 0.5)";
            inner_color = "rgba(230, 230, 230, 0.8)";
            font_color = "rgba(10, 10, 10, 1.0)";
            font_family = "SF Pro";
            placeholder_text = "Enter Password";
            fade_on_empty = true;
            fade_timeout = 1000;
            rounding = 20;
            position =  [0 200];
            halign = "center";
            valign = "center";
          }
        ];
      };
    };
  };
}
