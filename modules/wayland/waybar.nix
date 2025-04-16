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
            on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
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
            on-click = "pkill -SIGRTMIN+8 waybar && notify-send 'System Shutdown' 'Click again to confirm' && sleep 5 && pkill -SIGRTMIN+8 waybar";
            on-click-right = "systemctl poweroff";
            tooltip = false;
          };
        };
      };
      style = ''
        * {
          font-family: "SF Pro Nerd Font";
          font-size: 16px;
          font-weight: 600;
          color: #ffffff;
        }

        #clock, #memory {
          border-top-right-radius: 9999px;
          border-bottom-right-radius: 9999px;
        }

        #workspaces, #custom-power {
          border-top-left-radius: 9999px;
          border-bottom-left-radius: 9999px;
        }

        #clock, #network, #pulseaudio, #workspaces, #cpu, #temperature, #memory, #custom-power {
          background: rgba(36, 36, 36, 0.7);
          margin: 4px 0;
          padding: 0 10px;
        }

        #workspaces button.active {
          background: rgba(255, 255, 255, 0.7);
        }
      '';
    };
  };
}
