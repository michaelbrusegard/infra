{ config, lib, ... }:

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
          height = 24;
          modules-left = ["custom/power" "cpu" "temperature" "memory"];
          modules-right = ["hyprland/workspaces" "pulseaudio" "network" "clock"];

          "clock" = {
            format = " {:%d %b %H:%M}";
            tooltip = false;
          };

          "network" = {
            format-wifi = "󰤨";
            format-ethernet = "󰈀";
            format-disconnected = "󰤭";
            tooltip-format-wifi = "{essid}";
            tooltip-format-ethernet = "{ipaddr}";
            tooltip-format-disconnected = "Disconnected";
            on-click = "rofi-network-manager";
          };

          "pulseaudio" = {
            format = "{icon}";
            format-muted = "󰝟";
            format-icons = {
              default = ["󰕿" "󰖀" "󰕾"];
              headphone = "󰋋";
              headset = "󰋎";
              bluetooth = "󰂯";
            };
            on-click-right = "easyeffects";
          };

          "hyprland/workspaces" = {
            format = "{name}";
            on-click = "activate";
          };

          "cpu" = {
            interval = 5;
            format = " {usage}%";
            max-length = 10;
          };

          "temperature" = {
            interval = 5;
            format = " {temperatureC}°C";
          };

          "memory" = {
            interval = 10;
            format = " {used:0.1f}GB";
            tooltip = true;
            tooltip-format = "Used: {used:0.1f}GB\nTotal: {total:0.1f}GB";
          };

          "custom/power" = {
            format = "⏻";
            on-click = "rofi -show power-menu -modi power-menu:rofi-power-menu --choices=lockscreen/logout/reboot/shutdown --confirm=reboot/shutdown";
            tooltip = false;
          };
        };
      };
      style = ''
        * {
          font-family: "SF Pro Nerd Font";
          font-size: 16px;
          font-weight: 500;
          letter-spacing: 0.04em;
        }

        window#waybar {
          background: transparent;
        }

        box.modules-left {
          background: linear-gradient(90deg, rgba(255, 255, 255, 0.25) 0%, rgba(128, 128, 128, 0.25) 100%);
          border-radius: 9999px;
          padding-left: 4px;
          padding-right: 8px;
        }

        box.modules-right {
          background: linear-gradient(90deg, rgba(128, 128, 128, 0.25) 0%, rgba(0, 0, 0, 0.25) 100%);
          border-radius: 9999px;
          padding-left: 4px;
          padding-right: 8px;
        }

        #custom-power, #cpu, #temperature, #memory,
        #workspaces, #pulseaudio, #network, #clock {
          padding: 0 12px;
        }

        #workspaces button.active {
          background: #fff;
          color: #7e7e7e;
          border-radius: 8px;
        }

        #custom-power {
          font-size: 20px;
        }

        #pulseaudio, #network {
          font-size: 24px;
        }

        tooltip {
          border-radius: 10px;
          background-color: rgba(30, 30, 30, 0.87);
          border: 1px solid #7e7e7e;
          padding: 10px;
          box-shadow: 0 1px 4px rgba(0, 0, 0, 0.3);
          animation: fadeIn 0.2s ease-in-out;
        }

        tooltip label {
          font-size: 14px;
          padding: 2px 8px;
        }

        @keyframes fadeIn {
          from {
            opacity: 0;
          }
          to {
            opacity: 1;
          }
        }
      '';
    };
  };
}
