{
  flake.modules.nixos.hyprland =
    {
      lib,
      pkgs,
      ...
    }:
    {
      options.local.hyprland = {
        monitors = lib.mkOption {
          type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
          default = [ ];
        };

        lidSwitch = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.submodule {
              options = {
                name = lib.mkOption {
                  type = lib.types.str;
                  default = "Lid Switch";
                };
                output = lib.mkOption {
                  type = lib.types.str;
                };
              };
            }
          );
          default = null;
        };
      };

      config = {
        programs.hyprland = {
          enable = true;
          withUWSM = true;
          package = pkgs.hyprland.overrideAttrs (old: {
            postInstall = (old.postInstall or "") + ''
              substituteInPlace $out/share/wayland-sessions/hyprland.desktop \
                --replace-fail "[Desktop Entry]" "[Desktop Entry]
              NoDisplay=true"
              substituteInPlace $out/share/wayland-sessions/hyprland-uwsm.desktop \
                --replace-fail "Name=Hyprland (uwsm-managed)" "Name=Hyprland"
            '';
          });
        };
      };
    };

  flake.modules.homeManager.hyprland =
    {
      pkgs,
      lib,
      osConfig,
      ...
    }:
    let
      inherit (lib.generators) mkLuaInline;

      newTerminal = "${lib.getExe pkgs.ghostty} +new-window";
      nc = lib.getExe pkgs.netcat-openbsd;
      kanataPort = toString osConfig.services.kanata.keyboards.default.port;
      systemctl = lib.getExe' pkgs.systemd "systemctl";
      brightnessctl = lib.getExe pkgs.brightnessctl;
      kbdBacklightCycle = pkgs.writeShellScript "kbd-backlight-cycle" ''
        d='asus::kbd_backlight'
        b=$(${brightnessctl} -d "$d" g) || exit 0
        m=$(${brightnessctl} -d "$d" m)
        ${brightnessctl} -d "$d" s $(((b + 1) % (m + 1)))
      '';

      exec = cmd: mkLuaInline ''hl.dsp.exec_cmd("${cmd}")'';
      execRaw = cmd: mkLuaInline "hl.dsp.exec_cmd([[${cmd}]])";
      movefocus = dir: mkLuaInline ''hl.dsp.focus({ direction = "${dir}" })'';
      movewindow = dir: mkLuaInline ''hl.dsp.window.move({ direction = "${dir}" })'';
      focusWorkspace = n: mkLuaInline "hl.dsp.focus({ workspace = ${toString n} })";
      moveToWorkspace = n: mkLuaInline "hl.dsp.window.move({ workspace = ${toString n} })";
      togglefloating = mkLuaInline ''hl.dsp.window.float({ action = "toggle" })'';
      fullscreenToggle = mkLuaInline ''hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })'';
      # Toggles whether the focused window (RustDesk) can capture Hyprland binds.
      toggleShortcutsInhibit = mkLuaInline ''hl.dsp.window.set_prop({ prop = "no_shortcuts_inhibit", value = "toggle" })'';
      global = action: mkLuaInline ''hl.dsp.global("${action}")'';
      closewindow = mkLuaInline "hl.dsp.window.close()";
      killwindow = mkLuaInline "hl.dsp.window.kill()";
      drag = mkLuaInline "hl.dsp.window.drag()";
      resizeMouse = mkLuaInline "hl.dsp.window.resize()";

      bind = key: dsp: {
        _args = [
          key
          dsp
        ];
      };
      bindFlags = flags: key: dsp: {
        _args = [
          key
          dsp
          flags
        ];
      };
      bindLocked = bindFlags { locked = true; };
      bindLockedRepeat = bindFlags {
        locked = true;
        repeating = true;
      };
      bindMouse = bindFlags { mouse = true; };
      bindUninhibited = bindFlags { dont_inhibit = true; };

      workspaces = lib.range 1 9;

      lidSwitch = osConfig.local.hyprland.lidSwitch or null;
      lidMonitor =
        if lidSwitch != null then
          lib.lists.findFirst (m: m.output == lidSwitch.output) null osConfig.local.hyprland.monitors
        else
          null;
      lidBinds = lib.optionals (lidSwitch != null && lidMonitor != null) [
        (bindLocked "switch:on:${lidSwitch.name}" (exec "dms ipc call lock lock"))
      ];

      workspaceRules = [
        {
          class = "^(ardia)$";
          workspace = 2;
        }
        {
          class = "^(t3code|com\\.t3tools\\.T3Code)$";
          workspace = 1;
        }
        {
          class = "^(bulwark)$";
          workspace = 3;
        }
        {
          class = "^(discord)$";
          workspace = 5;
        }
        {
          class = "^(fluffychat)$";
          workspace = 5;
        }
        {
          class = "^(slack)$";
          workspace = 5;
        }
        {
          class = "^(signal)$";
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
          class = "^(feishin)$";
          workspace = 7;
        }
      ];
      simulatorRules = [
        {
          match.class = "^(Emulator|Simulator)$";
          float = true;
          pin = true;
        }
      ];
    in
    {
      home.packages = [ pkgs.wl-clipboard ];

      systemd.user.services = {
        netbird-ui = {
          Unit = {
            Description = "NetBird tray UI";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "/run/current-system/sw/bin/netbird-ui";
            Restart = "on-failure";
            RestartSec = 3;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        # The tray ships with the tailscale CLI; the module makes this user its
        # operator so the tray can log in and toggle the connection.
        tailscale-systray = {
          Unit = {
            Description = "Tailscale tray UI";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "/run/current-system/sw/bin/tailscale systray";
            Restart = "on-failure";
            RestartSec = 3;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      };

      wayland.windowManager.hyprland = {
        enable = true;
        package = null;
        portalPackage = null;
        systemd.variables = [ "--all" ];
        configType = "lua";

        # Kanata's layer follows gaming mode and the focused window. Gaming mode
        # drops the home-row mods and lets the touchpad work while keys are held,
        # so holding WASD works in games. Ghostty gets a layer without the Mac
        # text shortcuts because the shell does its own line editing.
        extraConfig = ''
          local gaming = false
          local kanataLayer

          local function syncKanata(window)
            local layer = "base"
            if gaming then
              layer = "nomods"
            elseif window and window.class == "com.mitchellh.ghostty" then
              layer = "terminal"
            end
            if layer == kanataLayer then
              return
            end
            kanataLayer = layer
            hl.exec_cmd(string.format(
              [[printf '{"ChangeLayer":{"new":"%s"}}' | ${nc} -N -w1 127.0.0.1 ${kanataPort}]],
              layer
            ))
          end

          hl.on("window.active", syncKanata)
          hl.on("hyprland.start", function() syncKanata(hl.get_active_window()) end)
          hl.on("config.reloaded", function() syncKanata(hl.get_active_window()) end)

          hl.bind("CTRL + SHIFT + G", function()
            gaming = not gaming
            hl.config({ input = { touchpad = { disable_while_typing = not gaming } } })
            syncKanata(hl.get_active_window())
            hl.notification.create({
              text = gaming and "Gaming mode ON" or "Gaming mode OFF",
              duration = 2000,
              color = gaming and "rgb(00ff00)" or "rgb(ff8800)",
            })
          end)
        '';

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
                render_power = 4;
                offset = "0 5";
                color = "0x00000070";
              };
            };

            animations.enabled = false;

            input = {
              kb_variant = "mac";
              repeat_rate = 65;
              repeat_delay = 150;
              accel_profile = "flat";
              sensitivity = -0.2;
              follow_mouse = 0;

              touchpad = {
                natural_scroll = true;
                scroll_factor = 0.3;
                disable_while_typing = true;
                clickfinger_behavior = true;
                tap_to_click = true;
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
              font_family = "GeistMono Nerd Font";
              mouse_move_enables_dpms = true;
              key_press_enables_dpms = true;
              middle_click_paste = false;
              focus_on_activate = true;
            };

            cursor.no_warps = true;
            binds.workspace_back_and_forth = true;
          };

          bind = [
            (bind "ALT + H" (movefocus "left"))
            (bind "ALT + J" (movefocus "down"))
            (bind "ALT + K" (movefocus "up"))
            (bind "ALT + L" (movefocus "right"))

            (bind "ALT + SHIFT + H" (movewindow "left"))
            (bind "ALT + SHIFT + J" (movewindow "down"))
            (bind "ALT + SHIFT + K" (movewindow "up"))
            (bind "ALT + SHIFT + L" (movewindow "right"))
          ]
          ++ map (n: bind "ALT + ${toString n}" (focusWorkspace n)) workspaces
          ++ map (n: bind "ALT + SHIFT + ${toString n}" (moveToWorkspace n)) workspaces
          ++ [
            (bind "ALT + 0" togglefloating)

            (bind "ALT + RETURN" (exec newTerminal))
            (bind "ALT + SHIFT + RETURN" (exec "dfiles open"))
            (bind "CTRL + SPACE" (exec "dms ipc call spotlight toggle"))
            (bind "CTRL + SHIFT + V" (exec "dms ipc call clipboard toggle"))
            (bind "CTRL + Q" closewindow)
            (bind "CTRL + SHIFT + Q" killwindow)
            (bind "CTRL + SUPER + Q" (exec "dms ipc call lock lock"))
            (bind "CTRL + SUPER + S" (exec "dms ipc call lock lock && ${systemctl} suspend"))
            (bind "CTRL + SUPER + F" fullscreenToggle)
            (bindUninhibited "ALT + ESCAPE" toggleShortcutsInhibit)
            (bind "CTRL + SHIFT + 3" (exec "dms screenshot full -d ~/Pictures/screenshots"))
            (bind "CTRL + SHIFT + 4" (exec "dms screenshot -d ~/Pictures/screenshots"))
            # T3 Code snapshot on both Shift keys. A key is not yet a modifier
            # when its own press is matched, so these fire only when the other
            # Shift is already held.
            (bind "SHIFT + Shift_L" (global "com.t3tools.T3Code:capture-window"))
            (bind "SHIFT + Shift_R" (global "com.t3tools.T3Code:capture-window"))

            (bindLockedRepeat "XF86AudioRaiseVolume" (exec "dms ipc call audio increment 3"))
            (bindLockedRepeat "XF86AudioLowerVolume" (exec "dms ipc call audio decrement 3"))
            (bindLockedRepeat "XF86MonBrightnessUp" (execRaw ''dms ipc call brightness increment 5 ""''))
            (bindLockedRepeat "XF86MonBrightnessDown" (execRaw ''dms ipc call brightness decrement 5 ""''))
            (bindLocked "XF86KbdLightOnOff" (exec "${kbdBacklightCycle}"))
            (bindLocked "XF86Launch1" (exec "dms ipc call color-picker toggle"))
            (bindLocked "XF86AudioMute" (exec "dms ipc call audio mute"))
            (bindLocked "XF86AudioMicMute" (exec "dms ipc call audio micmute"))
            (bindLocked "XF86AudioPlay" (exec "dms ipc call mpris playPause"))
            (bindLocked "XF86AudioPause" (exec "dms ipc call mpris playPause"))
            (bindLocked "XF86AudioNext" (exec "dms ipc call mpris next"))
            (bindLocked "XF86AudioPrev" (exec "dms ipc call mpris previous"))

            (bindMouse "ALT + mouse:272" drag)
            (bindMouse "ALT + mouse:273" resizeMouse)
          ]
          ++ lidBinds;

          window_rule =
            (map (r: {
              match = removeAttrs r [ "workspace" ];
              inherit (r) workspace;
            }) workspaceRules)
            ++ simulatorRules;
        };
      };
    };
}
