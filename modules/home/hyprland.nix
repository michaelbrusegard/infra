{
  pkgs,
  lib,
  osConfig,
  isWsl,
  ...
}: let
  inherit (lib.generators) mkLuaInline;

  wezterm = lib.getExe pkgs.wezterm;
  sh = lib.getExe' pkgs.bash "sh";
  yazi = lib.getExe pkgs.yazi;

  exec = cmd: mkLuaInline ''hl.dsp.exec_cmd("${cmd}")'';
  execRaw = cmd: mkLuaInline "hl.dsp.exec_cmd([[${cmd}]])";
  movefocus = dir: mkLuaInline ''hl.dsp.focus({ direction = "${dir}" })'';
  movewindow = dir: mkLuaInline ''hl.dsp.window.move({ direction = "${dir}" })'';
  focusWorkspace = n: mkLuaInline "hl.dsp.focus({ workspace = ${toString n} })";
  moveToWorkspace = n: mkLuaInline "hl.dsp.window.move({ workspace = ${toString n} })";
  togglefloating = mkLuaInline ''hl.dsp.window.float({ action = "toggle" })'';
  fullscreenToggle = mkLuaInline ''hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })'';
  resizeactive = x: y: mkLuaInline "hl.dsp.window.resize({ x = ${toString x}, y = ${toString y}, relative = true })";
  closewindow = mkLuaInline "hl.dsp.window.close()";
  killwindow = mkLuaInline "hl.dsp.window.kill()";
  drag = mkLuaInline "hl.dsp.window.drag()";
  resizeMouse = mkLuaInline "hl.dsp.window.resize()";

  bind = key: dsp: {_args = [key dsp];};
  bindFlags = flags: key: dsp: {_args = [key dsp flags];};
  bindRepeat = bindFlags {repeating = true;};
  bindLocked = bindFlags {locked = true;};
  bindLockedRepeat = bindFlags {
    locked = true;
    repeating = true;
  };
  bindMouse = bindFlags {mouse = true;};

  workspaces = lib.range 1 9;

  workspaceRules = [
    {
      class = "^(zen-beta)$";
      workspace = 2;
    }
    {
      class = "^(Proton Mail)$";
      workspace = 3;
    }
    {
      class = "^(Proton Pass)$";
      workspace = 3;
    }
    {
      class = "^(libreoffice)$";
      workspace = 4;
    }
    {
      class = "^(legcord)$";
      workspace = 5;
    }
    {
      class = "^(Element)$";
      workspace = 5;
    }
    {
      class = "^(Slack)$";
      workspace = 5;
    }
    {
      class = "^(Signal)$";
      workspace = 5;
    }
    {
      class = "^(zenity)$";
      workspace = 6;
    }
    {
      class = "^(OrcaSlicer)$";
      workspace = 6;
    }
    {
      class = "^(resolve)$";
      workspace = 6;
    }
    {
      class = "^(Gimp)$";
      workspace = 6;
    }
    {
      class = "^(org.inkscape.Inkscape)$";
      workspace = 6;
    }
    {
      class = "^(scribus)$";
      workspace = 6;
    }
    {
      class = "^(org.freecad.FreeCAD)$";
      workspace = 6;
    }
  ];
in
  lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
    # Upstream netbird.desktop ships `Exec=netbird-ui`, but the NixOS module
    # only renames Name/Icon, leaving Exec pointing at a binary that isn't on
    # PATH. The per-client wrapper `netbird-ui-default` carries the
    # `--daemon-addr` the launcher needs, so override the entry to call it.
    xdg.desktopEntries."netbird-default" = {
      name = "NetBird @ netbird-default";
      exec = "netbird-ui-default";
      icon = "netbird";
      terminal = false;
      type = "Application";
      categories = ["Utility"];
    };

    systemd.user.services.netbird-ui = {
      Unit = {
        Description = "NetBird tray UI";
        PartOf = ["graphical-session.target"];
        After = ["graphical-session.target"];
      };
      Service = {
        ExecStart = "/run/current-system/sw/bin/netbird-ui-default";
        Restart = "on-failure";
        RestartSec = 3;
      };
      Install.WantedBy = ["graphical-session.target"];
    };

    wayland.windowManager.hyprland = {
      enable = true;
      package = null;
      portalPackage = null;
      systemd.variables = ["--all"];
      configType = "lua";

      settings = {
        monitor = osConfig.local.hyprland.monitors;

        config = {
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
            rounding = 12;
            blur.enabled = false;
            shadow = {
              range = 30;
              render_power = 5;
              offset = "0 5";
              color = "0x00000070";
            };
          };

          animations.enabled = false;

          input = {
            kb_variant = "mac";
            kb_options = "lv3:lalt_switch";
            repeat_rate = 65;
            repeat_delay = 150;
            accel_profile = "flat";
            sensitivity = -0.2;
            follow_mouse = 0;

            touchpad = {
              natural_scroll = true;
              scroll_factor = 0.3;
              disable_while_typing = true;
            };
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
            disable_watchdog_warning = true;
            font_family = "GoogleSansCode Nerd Font";
            mouse_move_enables_dpms = true;
            key_press_enables_dpms = true;
            middle_click_paste = false;
          };

          cursor.no_warps = true;
          binds.workspace_back_and_forth = true;
        };

        bind =
          [
            # Focus window
            (bind "MOD5 + H" (movefocus "left"))
            (bind "MOD5 + J" (movefocus "down"))
            (bind "MOD5 + K" (movefocus "up"))
            (bind "MOD5 + L" (movefocus "right"))

            # Move window
            (bind "MOD5 + SHIFT + H" (movewindow "left"))
            (bind "MOD5 + SHIFT + J" (movewindow "down"))
            (bind "MOD5 + SHIFT + K" (movewindow "up"))
            (bind "MOD5 + SHIFT + L" (movewindow "right"))
          ]
          ++ map (n: bind "MOD5 + ${toString n}" (focusWorkspace n)) workspaces
          ++ map (n: bind "MOD5 + SHIFT + ${toString n}" (moveToWorkspace n)) workspaces
          ++ [
            (bind "MOD5 + 0" togglefloating)

            # System
            (bind "MOD5 + RETURN" (exec "${wezterm} start --always-new-process"))
            (bind "MOD5 + SHIFT + RETURN"
              (execRaw "${wezterm} start --always-new-process -e ${sh} -c '${yazi}'"))
            (bind "SUPER + SPACE" (exec "dms ipc call spotlight toggle"))
            (bind "SUPER + SHIFT + V" (exec "dms ipc call clipboard toggle"))
            (bind "SUPER + Q" closewindow)
            (bind "SUPER + SHIFT + Q" killwindow)
            (bind "SUPER + CTRL + Q" (exec "dms ipc call lock lock"))
            (bind "SUPER + CTRL + F" fullscreenToggle)
            (bind "SUPER + SHIFT + 3" (exec "dms screenshot full -d ~/Pictures/screenshots"))
            (bind "SUPER + SHIFT + 4" (exec "dms screenshot -d ~/Pictures/screenshots"))

            # Resize
            (bindRepeat "MOD5 + left" (resizeactive (-20) 0))
            (bindRepeat "MOD5 + down" (resizeactive 0 20))
            (bindRepeat "MOD5 + up" (resizeactive 0 (-20)))
            (bindRepeat "MOD5 + right" (resizeactive 20 0))

            # Audio/brightness
            (bindLockedRepeat "XF86AudioRaiseVolume" (exec "dms ipc call audio increment 3"))
            (bindLockedRepeat "XF86AudioLowerVolume" (exec "dms ipc call audio decrement 3"))
            (bindLockedRepeat "XF86MonBrightnessUp" (execRaw ''dms ipc call brightness increment 5 ""''))
            (bindLockedRepeat "XF86MonBrightnessDown" (execRaw ''dms ipc call brightness decrement 5 ""''))
            (bindLocked "XF86AudioMute" (exec "dms ipc call audio mute"))
            (bindLocked "XF86AudioMicMute" (exec "dms ipc call audio micmute"))
            (bindLocked "XF86AudioPlay" (exec "dms ipc call mpris playPause"))
            (bindLocked "XF86AudioPause" (exec "dms ipc call mpris playPause"))
            (bindLocked "XF86AudioNext" (exec "dms ipc call mpris next"))
            (bindLocked "XF86AudioPrev" (exec "dms ipc call mpris previous"))

            # Mouse
            (bindMouse "MOD5 + mouse:272" drag)
            (bindMouse "MOD5 + mouse:273" resizeMouse)
          ];

        window_rule =
          map (r: {
            match.class = r.class;
            inherit (r) workspace;
          })
          workspaceRules;
      };
    };
  }
