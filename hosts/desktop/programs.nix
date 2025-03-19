{ config, pkgs, system, hyprland, catppuccin, ... }: {
  programs = {
    hyprland = {
      enable = true;
      xwayland.enable = true;
      package = hyprland.packages.${system}.hyprland;
      portalPackage = hyprland.packages.${system}.xdg-desktop-portal-hyprland;
    };
    catppuccin.hyprland = {
      enable = true;
      accent = "blue";
    };
    hyprlock = {
      enable = true;
      settings = {
        general = {
          ignore_empty_input = true;
          grace = 300;
          disable_loading_bar = true;
        };
        background = [
          {
            path = "../../assets/Twillight Peaks.png";
          }
        ];
        label = [
          {
            text = "cmd[update:1000] date '+%A %d %B'";
            color = "rgba(255, 255, 255, 0.8)";
            font_size = 24;
            font_family = "SF Pro";
            position = {
              x = 0;
              y = -220;
            };
            halign = "center";
            valign = "center";
          }
          {
            text = "cmd[update:1000] date '+%H:%M'";
            color = "rgba(255, 255, 255, 1.0)";
            font_size = 96;
            font_family = "SF Pro";
            position = {
              x = 0;
              y = -140;
            };
            halign = "center";
            valign = "center";
          }
        ];
        input-field = [
          {
            size = {
              width = 300;
              height = 50;
            };
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
            position = {
              x = 0;
              y = 100;
            };
            halign = "center";
            valign = "center";
        }
      ];
      };
    };
    catppuccin.hyprlock = {
      enable = true;
      accent = "blue";
    };
    waybar = {
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
      style = {};
    };
    catppuccin.waybar = {
      enable = true;
      mode = "prependImport";
    };
    rofi = {
      enable = true;
      location = "center";
      yoffset = -200;
      terminal = "${pkgs.wezterm}/bin/wezterm";
      font = "SF Pro Nerd Font";
      theme = let
        inherit (config.lib.formats.rasi) mkLiteral;
      in {
        "*" = {
          bg0 = mkLiteral "#242424E6";
          bg1 = mkLiteral "#7E7E7E80";
          bg2 = mkLiteral "#0860f2E6";
          fg0 = mkLiteral "#DEDEDE";
          fg1 = mkLiteral "#FFFFFF";
          fg2 = mkLiteral "#DEDEDE80";
          "background-color" = mkLiteral "transparent";
          "text-color" = mkLiteral "@fg0";
          margin = 0;
          padding = 0;
          spacing = 0;
        };
        "window" = {
          "background-color" = mkLiteral "@bg0";
          location = mkLiteral "center";
          width = 640;
          "border-radius" = 8;
        };
        "inputbar" = {
          padding = mkLiteral "12px";
          spacing = mkLiteral "12px";
          children = map mkLiteral [ "icon-search" "entry" ];
        };
        "icon-search" = {
          expand = false;
          filename = mkLiteral "\"Search for apps\"";
          size = mkLiteral "28px";
        };
        "icon-search, entry, element-icon, element-text" = {
          "vertical-align" = mkLiteral "0.5";
        };
        "entry" = {
          font = mkLiteral "inherit";
          placeholder = mkLiteral "\"Search\"";
          "placeholder-color" = mkLiteral "@fg2";
        };
        "message" = {
          border = mkLiteral "2px 0 0";
          "border-color" = mkLiteral "@bg1";
          "background-color" = mkLiteral "@bg1";
        };
        "textbox" = {
          padding = mkLiteral "8px 24px";
        };
        "listview" = {
          lines = 10;
          columns = 1;
          "fixed-height" = false;
          border = mkLiteral "1px 0 0";
          "border-color" = mkLiteral "@bg1";
        };
        "element" = {
          padding = mkLiteral "8px 16px";
          spacing = mkLiteral "16px";
          "background-color" = mkLiteral "transparent";
        };
        "element normal active" = {
          "text-color" = mkLiteral "@bg2";
        };
        "element alternate active" = {
          "text-color" = mkLiteral "@bg2";
        };
        "element selected normal, element selected active" = {
          "background-color" = mkLiteral "@bg2";
          "text-color" = mkLiteral "@fg1";
        };
        "element-icon" = {
          size = mkLiteral "1em";
        };
        "element-text" = {
          "text-color" = mkLiteral "inherit";
        };
      };
    };
    catppuccin.rofi.enable = true;
    yubikey-touch-detector.enable = true;
  };
}
