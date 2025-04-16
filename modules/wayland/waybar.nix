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
          height = 22;
          margin = "16 16";
          modules-left = ["custom/launcher" "cpu" "temperature" "memory"];
          modules-center = ["hyprland/workspaces"];
          modules-right = ["backlight" "pulseaudio" "network" "battery" "clock" "custom/power"];

          "custom/launcher" = {
            format = " ";
            tooltip = false;
          };

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
            format-disconnected = "睊 Disconnected";
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
          };

          "custom/power" = {
            format = "";
            tooltip = false;
          };
        };
      };

      style = ''
        * {
          min-height: 0;
          font-family: "Noto Sans";
          font-size: 10px;
          border: none;
          border-radius: 3px;
        }

        window#waybar {
          background-color: transparent;
          border-top: 8px transparent;
          border-radius: 8px;
          color: #ffffff;
          transition-property: background-color;
          transition-duration: 5s;
        }

        window#waybar.hidden {
          opacity: 0.2;
        }

        #workspaces button {
          background-color: #1e2021;
          color: #b5e8e0;
          margin: 4px 2px 0 2px;
          min-width: 32px;
          padding: 2px 0 0 0;
        }

        #workspaces button.active {
          background: linear-gradient(220deg, rgba(248,189,150,1) 0%, rgba(181,232,224,1) 49%, rgba(0,212,255,1) 100%);
          color: #1e2021;
        }

        #workspaces button:hover {
          color: #b4befe;
        }

        #workspaces button.focused {
          background-color: #bbccdd;
          color: #1e2021;
        }

        #workspaces button.urgent {
          background-color: #fae3b0;
        }

        #network {
          background: #1e2021;
          color: #bd93f9;
          margin: 4px 0 0 4px;
          padding: 0 10px;
        }

        #pulseaudio {
          background: #1e2021;
          color: #fae3b0;
          margin: 4px 0 0 4px;
          padding: 0 10px;
        }

        #battery {
          background: #1e2021;
          color: #b5e8e0;
          margin: 4px 0 0 4px;
          padding: 0 7px 0 5px;
        }

        #battery.charging, #battery.plugged {
          background-color: #1e2021;
          color: #b5e8e0;
        }

        #backlight {
          background: #1e2021;
          color: #f8bd96;
          margin: 4px 0 0 4px;
          padding: 0 10px;
        }

        #clock {
          background: #1e2021;
          color: #abe9b3;
          margin: 4px 0 0 4px;
          padding: 0 7px 0 5px;
        }

        #memory {
          background: #1e2021;
          color: #ddb6f2;
          margin: 4px 0 0 4px;
          padding: 0 10px;
        }

        #temperature {
          background: #1e2021;
          color: #f8bd96;
          margin: 4px 0 0 4px;
          padding: 0 10px;
        }

        #cpu {
          background: #1e2021;
          color: #96cdfb;
          margin: 4px 0 0 4px;
          padding: 0 10px;
        }

        #custom-launcher {
          background: #1e2021;
          color: #fae3b0;
          font-size: 15px;
          margin: 4px 0 0 4px;
          padding: 0 3px 0 11px;
        }

        #custom-power {
          background: #1e2021;
          color: #f28fad;
          font-size: 10px;
          margin: 4px 4px 0 4px;
          padding: 2px 10px 0 10px;
        }
      '';
    };
  };
}
