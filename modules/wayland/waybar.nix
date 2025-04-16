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
          gtk-layer-shell = true;
          layer = "top";
          height = 28;
          margin = "4 4";
          modules-left = ["cpu" "temperature" "memory"];
          modules-center = ["hyprland/workspaces"];
          modules-right = ["backlight" "pulseaudio" "network" "battery" "clock" "custom/power"];

          "cpu" = {
            interval = 5;
            format = " {usage}%";
            max-length = 10;
          };

          "temperature" = {
            interval = 5;
            tooltip = false;
            format = " {temperatureC}°C";
            max-length = 10;
          };

          "memory" = {
            interval = 10;
            format = " {}%";
            max-length = 10;
          };

          "hyprland/workspaces" = {
            format = "{name}";
            on-click = "activate";
          };

          "backlight" = {
            format = "{icon} {percent}%";
            format-icons = ["" "" "" ""];
            on-scroll-up = "light -A 5";
            on-scroll-down = "light -U 5";
            interval = 2;
          };

          "pulseaudio" = {
            format = "{icon} {volume}%";
            format-muted = "婢 muted";
            format-icons = {
              default = ["" "奔" "墳"];
            };
            on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          };

          "network" = {
            format-wifi = " {essid}";
            format-ethernet = " {ipaddr}";
            format-disconnected = "睊";
            tooltip = false;
          };

          "battery" = {
            states = {
              good = 95;
              warning = 30;
              critical = 20;
            };
            format = "{icon} {capacity}%";
            format-charging = " {capacity}%";
            format-plugged = " {capacity}%";
            format-icons = ["" "" "" "" ""];
          };

          "clock" = {
            format = " {:%H:%M}";
            format-alt = " {:%a, %d %b}";
            tooltip = false;
          };

          "custom/power" = {
            format = "⏻";
            on-click = "rofi -show power-menu -modi power-menu:~/.local/bin/rofi-power-menu";
            tooltip = false;
          };
        };
      };

      style = ''
        * {
          min-height: 0;
          font-family: "SF Pro Nerd Font";
          font-size: 13px;
          border: none;
          border-radius: 6px;
        }

        window#waybar {
          background-color: rgba(36, 36, 36, 0.90);
          border-radius: 8px;
          color: #dedede;
          margin: 4px;
          transition-property: background-color;
          transition-duration: 0.5s;
        }

        window#waybar.hidden {
          opacity: 0.2;
        }

        #workspaces button {
          background-color: transparent;
          color: #dedede;
          margin: 4px 2px;
          min-width: 24px;
          padding: 2px 0;
        }

        #workspaces button.active {
          background: #0860f2e6;
          color: #ffffff;
        }

        #workspaces button:hover {
          color: #ffffff;
          background: rgba(8, 96, 242, 0.2);
        }

        #workspaces button.focused {
          background: #0860f2e6;
          color: #ffffff;
        }

        #workspaces button.urgent {
          background-color: #eb4d4b;
        }

        #network,
        #pulseaudio,
        #battery,
        #backlight,
        #clock,
        #memory,
        #temperature,
        #cpu,
        #custom-power {
          background: rgba(36, 36, 36, 0.7);
          color: #dedede;
          margin: 4px 2px;
          padding: 0 10px;
        }

        #battery.charging, #battery.plugged {
          color: #26a65b;
        }

        #battery.critical:not(.charging) {
          color: #eb4d4b;
          animation: blink 0.5s linear infinite alternate;
        }

        #custom-power {
          color: #eb4d4b;
          margin-right: 4px;
          font-size: 15px;
        }

        @keyframes blink {
          to {
            background-color: #ff0000;
            color: #ffffff;
          }
        }
      '';
    };
  };
}
