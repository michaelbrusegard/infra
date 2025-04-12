{ config, lib, ... }:

let
  cfg = config.modules.wayland;
in {
  config = lib.mkIf cfg.enable {
    wayland.windowManager.hyprland = {
      enable = true;
      xwayland.enable = true;
      settings = {
        env = [
          "NIXOS_OZONE_WL,1"
        ];
        exec-once = [ 
          "wl-paste --type text --watch cliphist store"
          "wl-paste --type image --watch cliphist store"
        ];
        monitor = [
          "DP-1,3440x1440@144,0x0,1"
          "DP-3,2560x1440@144,3440x0,1"
        ];
        general = {
          border_size = 2;
          gaps_in = 3;
          gaps_out = 6;
          resize_on_border = true;
          no_focus_fallback = true;
          "col.active_border" = "0xff89b4fa";
          "col.inactive_border" = "0xff45475a";
        };
        decoration = {
          rounding = 10;
          blur.enabled = false;
          shadow = {
            range = 20;
            render_power = 3;
            ignore_window = true;
            offset = "0 4";
            scale = 0.97;
            color = "0x66000000";
          };
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
          groupbar = {
            enabled = false;
            render_titles = false;
          };
        };
        misc = {
          disable_hyprland_logo = true;
          disable_splash_rendering = true;
          font_family = "SF Pro Nerd Font";
          mouse_move_enables_dpms = true;
          key_press_enables_dpms = true;
          disable_autoreload = true;
          middle_click_paste = false;
        };
        cursor = {
          no_warps = true;
        };
        binds.workspace_back_and_forth = true;
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
          "super, c, exec, wl-copy"
          "super, v, exec, wl-paste"
          "super shift, v, exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy"
          "super, q, killactive,"
          "super ctrl, q, exec, loginctl lock-session"
        ];
        bindm = [
          "alt, mouse:272, movewindow"
          "alt, mouse:273, resizewindow"
        ];
        bindl = [
          ", XF86AudioNext, exec, playerctld next"
          ", XF86AudioPause, exec, playerctld play-pause"
          ", XF86AudioPlay, exec, playerctld play-pause"
          ", XF86AudioPrev, exec, playerctld previous"
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
    catppuccin.hyprland = {
      enable = true;
      accent = "blue";
    };
  };
}
