{ config, lib, pkgs, hyprland, apple-fonts, system, ... }:

let
  cfg = config.modules.hyprland;
in {
  options.modules.hyprland.enable = lib.mkEnableOption "Hyprland configuration";

  config = lib.mkIf cfg.enable {
    gtk = {
      enable = true;
      font = {
        name = "SF Pro";
        package = apple-fonts.packages.${system}.sf-pro;
      };
    };
    qt = {
      enable = true;
      style.name = "adwaita-dark";
    };
    wayland.windowManager.hyprland = {
      enable = true;
      xwayland.enable = true;
      package = hyprland.packages.${system}.hyprland;
      settings = {
        env = [
          "NIXOS_OZONE_WL,1"
          "XDG_CURRENT_DESKTOP,hyprland"
          "XDG_SESSION_TYPE,wayland"
          "XDG_SESSION_DESKTOP,hyprland"
          "QT_QPA_PLATFORM,wayland"
        ];
        exec-once = [ 
          "waybar"
          "wl-paste --type text --watch cliphist store"
          "wl-paste --type image --watch cliphist store"
        ];
        general = {
          border_size = 5;
          gaps_in = 6;
          gaps_out = 12;
          resize_on_border = true;
          no_focus_fallback = true;
          col.active_border = "0xFF007AFF";
          col.inactive_border = "0xff45475a";
        };
        decoration = {
          rounding = 10;
        };
        blur = {
          enabled = false;
        };
        shadow = {
          range = 20;
          render_power = 3;
          ignore_window = true;
          offset = "0 4";
          scale = 0.97;
          color = "0x66000000";
        };
        animations = {
          enabled = false;
          first_launch_animation = false;
        };
        input = {
          repeat_rate = 65;
          repeat_delay = 150;
          follow_mouse = 1;
        };
        group = {
          auto_group = false;
        };
        groupbar = {
          enabled = false;
        };
        misc = {
          disable_hyprland_logo = true;
          disable_splash_rendering = true;
          font-family = "SF Pro Nerd Font";
          mouse_move_enables_dpms = true;
          key_press_enables_dpms = true;
          disable_autoreload = true;
          middle_click_paste = false;
        };
        binds.workspace_back_and_forth = true;
        xwayland.enabled = true;
        bind = [
          # Focus window
          "alt, h, movefocus, l"
          "alt, l, movefocus, r"
          "alt, j, movefocus, u"
          "alt, k, movefocus, d"

          # Move window
          "alt shift, h, movewindow, l"
          "alt shift, l, movewindow, r"
          "alt shift, j, movewindow, d"
          "alt shift, k, movewindow, u"

          # Resize window
          "alt ctrl, h, resizeactive, -50 0"
          "alt ctrl, j, resizeactive, 0 50"
          "alt ctrl, k, resizeactive, 0 -50"
          "alt ctrl, l, resizeactive, 50 0"

          # Switch to specific workspace
          "alt, 1, workspace, 1"
          "alt, 2, workspace, 2"
          "alt, 3, workspace, 3"
          "alt, 4, workspace, 4"
          "alt, 5, workspace, 5"
          "alt, 6, workspace, 6"
          "alt, 7, workspace, 7"
          "alt, 8, workspace, 8"
          "alt, 9, workspace, 9"

          # Move window to specific workspace
          "alt shift, 1, movetoworkspace, 1"
          "alt shift, 2, movetoworkspace, 2"
          "alt shift, 3, movetoworkspace, 3"
          "alt shift, 4, movetoworkspace, 4"
          "alt shift, 5, movetoworkspace, 5"
          "alt shift, 6, movetoworkspace, 6"
          "alt shift, 7, movetoworkspace, 7"
          "alt shift, 8, movetoworkspace, 8"
          "alt shift, 9, movetoworkspace, 9"

          # Toggle Floating Window
          "alt, 0, togglefloating,"

          # Change between dwindle and master layout for space
          "alt, comma, exec, hyprctl keyword general:layout dwindle"
          "alt, slash, exec, hyprctl keyword general:layout master"

          # System
          "alt, return, exec, wezterm"
          "alt shift, return, exec, wezterm -e sh -c 'yazi'"
          "super, space, exec, rofi -show drun"
          "super shift, v, exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy"
          "super, q, killactive,"
          "super shift, 1, exec, hyprlock"
        ];
        bindm = [
          "alt, mouse:272, movewindow"
          "alt, mouse:273, resizewindow"
        ];
        bindl = [
          ", XF86AudioNext, exec, playerctl next"
          ", XF86AudioPause, exec, playerctl play-pause"
          ", XF86AudioPlay, exec, playerctl play-pause"
          ", XF86AudioPrev, exec, playerctl previous"
        ];
        windowrulev2 = [
          "workspace 2, class:^(Zen Browser)$"
          "workspace 3, class:^(Proton Mail)$"
          "workspace 4, class:^(Obsidian)$"
          "workspace 5, class:^(Legcord)$"
          "workspace 5, class:^(Element)$"
          "workspace 5, class:^(Slack)$"
          "workspace 7, class:^(Resolve)$"
        ];
      };
    };
    programs = {
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
    };
    home.packages = with pkgs; [
      wl-clipboard
      cliphist
      mako
      libnotify
      swww
      playerctl
    ];
    catppuccin = {
      gtk = {
        enable = true;
        accent = "blue";
        icon = {
          enable = true;
          accent = "blue";
        };
        size = "compact";
        tweaks = [ "rimless" ];
      };
      hyprland = {
        enable = true;
        accent = "blue";
      };
      hyprlock = {
        enable = true;
        accent = "blue";
      };
      waybar = {
        enable = true;
        mode = "prependImport";
      };
      rofi.enable = true;
      mako = {
        enable = true;
        accent = "blue";
      };
    };
  };
}
