{ pkgs, config, lib, ... }:

let
  cfg = config.modules.wayland;
in {
  config = lib.mkIf cfg.enable {
    wayland.windowManager.hyprland = {
      enable = true;
      package = null;
      portalPackage = null;
      xwayland.enable = true;
      systemd.variables = [ "--all" ];
      settings = {
        monitor = [
          "DP-1,3440x1440@144,0x0,1, bitdepth, 10"
          "DP-3,2560x1440@144,3440x0,1, bitdepth, 10"
        ];
        exec-once = [
          "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store"
          "${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store"
        ];
        ecosystem = {
          no_update_news = true;
          no_donation_nag = true;
        };
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
        animations.enabled = false;
        input = {
          kb_layout = "us";
          kb_variant = "mac";
          kb_options = "lv3:lalt_switch";
          repeat_rate = 65;
          repeat_delay = 150;
          accel_profile = "flat";
          sensitivity = -0.2;
          follow_mouse = 0;
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
          font_family = "SFPro Nerd Font";
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
          "mod5, h, movefocus, l"
          "mod5, j, movefocus, d"
          "mod5, k, movefocus, u"
          "mod5, l, movefocus, r"

          # Move window
          "mod5 shift, h, movewindow, l"
          "mod5 shift, j, movewindow, d"
          "mod5 shift, k, movewindow, u"
          "mod5 shift, l, movewindow, r"

          # Switch to specific workspace
          "mod5, 1, workspace, 1"
          "mod5, 2, workspace, 2"
          "mod5, 3, workspace, 3"
          "mod5, 4, workspace, 4"
          "mod5, 5, workspace, 5"
          "mod5, 6, workspace, 6"
          "mod5, 7, workspace, 7"
          "mod5, 8, workspace, 8"
          "mod5, 9, workspace, 9"

          # Move window to specific workspace
          "mod5 shift, 1, movetoworkspace, 1"
          "mod5 shift, 2, movetoworkspace, 2"
          "mod5 shift, 3, movetoworkspace, 3"
          "mod5 shift, 4, movetoworkspace, 4"
          "mod5 shift, 5, movetoworkspace, 5"
          "mod5 shift, 6, movetoworkspace, 6"
          "mod5 shift, 7, movetoworkspace, 7"
          "mod5 shift, 8, movetoworkspace, 8"
          "mod5 shift, 9, movetoworkspace, 9"

          # Toggle floating window
          "mod5, 0, togglefloating,"

          # System
          "mod5, return, exec, ${pkgs.wezterm}/bin/wezterm start --always-new-process"
          "mod5 shift, return, exec, ${pkgs.wezterm}/bin/wezterm start --always-new-process -e ${pkgs.bash}/bin/sh -c '${pkgs.yazi}/bin/yazi'"
          "super, space, exec, ${pkgs.rofi}/bin/rofi -show drun"
          "super, tab, exec, ${pkgs.cliphist}/bin/cliphist list | ${pkgs.rofi}/bin/rofi -dmenu | ${pkgs.cliphist}/bin/cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy"
          "super, q, exec, ${pkgs.hyprland}/bin/hyprctl dispatch killactive"
          "super shift, q, exec, ${pkgs.hyprland}/bin/hyprctl dispatch killactive; WID=$(${pkgs.jq}/bin/jq -r .class <<< $(${pkgs.hyprland}/bin/hyprctl activewindow -j)); ${pkgs.coreutils}/bin/pkill -KILL -f \"$WID\""
          "super ctrl, q, exec, loginctl lock-session"
          "super ctrl, f, fullscreen, 0"
          "super shift, 3, exec, ${pkgs.grim}/bin/grim -t png -o $(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '\''.[] | select(.focused) | .name'\'') \"$HOME/Pictures/screenshots/Screenshot $(${pkgs.coreutils}/bin/date +'\''%Y-%m-%d at %H.%M.%S'\'').png\""
          "super shift, 4, exec, ${pkgs.grim}/bin/grim -t png -g \"$(${pkgs.slurp}/bin/slurp -d -w 0)\" \"$HOME/Pictures/screenshots/Screenshot $(${pkgs.coreutils}/bin/date +'\''%Y-%m-%d at %H.%M.%S'\'').png\""
        ];
        binde = [
          # Resize window
          "mod5, left, resizeactive, -20 0"
          "mod5, down, resizeactive, 0 20"
          "mod5, up, resizeactive, 0 -20"
          "mod5, right, resizeactive, 20 0"
        ];
        bindm = [
          "mod5, mouse:272, movewindow"
          "mod5, mouse:273, resizewindow"
        ];
        bindl = [
          ", XF86AudioNext, exec, ${pkgs.playerctl}/bin/playerctld next"
          ", XF86AudioPause, exec, ${pkgs.playerctl}/bin/playerctld play-pause"
          ", XF86AudioPlay, exec, ${pkgs.playerctl}/bin/playerctld play-pause"
          ", XF86AudioPrev, exec, ${pkgs.playerctl}/bin/playerctld previous"
        ];
        windowrulev2 = [
          "workspace 2, class:^(vivaldi-stable)$"
          "workspace 3, class:^(Proton Mail)$"
          "workspace 3, class:^(Proton Pass)$"
          "workspace 4, class:^(obsidian)$"
          "workspace 4, class:^(libreoffice)$"
          "workspace 4, class:^(Notion)$"
          "workspace 5, class:^(legcord)$"
          "workspace 5, class:^(Element)$"
          "workspace 5, class:^(Slack)$"
          "workspace 6, class:^(zenity)$"
          "workspace 6, class:^(OrcaSlicer)$"
          "workspace 6, class:^(resolve)$"
          "workspace 6, class:^(Gimp)$"
          "workspace 6, class:^(org.inkscape.Inkscape)$"
          "workspace 6, class:^(scribus)$"
          "workspace 6, class:^(org.freecad.FreeCAD)$"
        ];
      };
    };
  };
}
