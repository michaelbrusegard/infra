{ config, lib, ... }:

let
  cfg = config.modules.wayland;
in {
  config = lib.mkIf cfg.enable {
    programs = {
      waybar = {
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
              on-scroll-up = "wpctl set-volume @DEFAULT_AUDIO_SINK@ +5%";
              on-scroll-down = "wpctl set-volume @DEFAULT_AUDIO_SINK@ -5%";
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
              on-click = "wlogout";
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
            background-color: rgba(36, 36, 36, 0.75);
            border: 1px solid #7e7e7e;
            padding: 10px;
            box-shadow: 0 2px 12px rgba(0, 0, 0, 0.4);
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
      wlogout = {
        enable = true;
        layout = [
          {
              label = "lock";
              action = "loginctl lock-session";
              text = "Lock";
              keybind = "l";
          }
          {
              label = "logout";
              action = "loginctl terminate-user $USER";
              text = "Logout";
              keybind = "e";
          }
          {
              label = "shutdown";
              action = "systemctl poweroff";
              text = "Shutdown";
              keybind = "s";
          }
          {
              label = "reboot";
              action = "systemctl reboot";
              text = "Reboot";
              keybind = "r";
          }
        ];
        style = ''
          * {
            background-image: none;
            box-shadow: none;
            font-family: "SF Pro Nerd Font";
          }

          window {
            background-color: rgba(28, 28, 28, 0.8);
          }

          button {
            color: #fff;
            background-color: rgba(255, 255, 255, 0.05);
            border: none;
            border-radius: 12px;
            margin: 8px;
            padding: 16px;
            font-size: 16px;
            font-weight: 500;
            animation: fadeIn 0.2s ease-in-out;
            transition: all 0.2s ease;
            background-size: 36px;
            background-repeat: no-repeat;
            background-position: center 32px;
            padding-top: 80px;
          }

          button:hover {
            background-color: rgba(255, 255, 255, 0.1);
            transform: scale(1.02);
          }

          button:focus {
            background-color: rgba(255, 255, 255, 0.1);
            outline: none;
          }

          #lock {
            background-image: image(url("/usr/share/wlogout/icons/lock.png"), url("/usr/local/share/wlogout/icons/lock.png"));
          }

          #logout {
            background-image: image(url("/usr/share/wlogout/icons/logout.png"), url("/usr/local/share/wlogout/icons/logout.png"));
          }

          #shutdown {
            background-image: image(url("/usr/share/wlogout/icons/shutdown.png"), url("/usr/local/share/wlogout/icons/shutdown.png"));
          }

          #reboot {
            background-image: image(url("/usr/share/wlogout/icons/reboot.png"), url("/usr/local/share/wlogout/icons/reboot.png"));
          }

          @keyframes fadeIn {
            from { opacity: 0; }
            to { opacity: 1; }
          }
        '';
      };
    };
    home.packages = with pkgs; [
      easyeffects
    ];
  };
}
