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
          modules-left = ["custom/power" "cpu" "memory" "custom/cputemp" "custom/gpu" "custom/vram" "custom/gputemp"];
          modules-right = ["hyprland/workspaces" "pulseaudio" "network" "clock"];

          "clock" = {
            format = " {:%d %b %H:%M}";
            tooltip-format = "{:%A, %B %d, %Y\nWeek %V\n%H:%M:%S}";
          };

          "network" = {
            format-wifi = "<span size='large'>󰤨</span>";
            format-ethernet = "<span size='large'>󰈀</span>";
            format-disconnected = "<span size='large'>󰤭</span>";
            tooltip-format-wifi = "{essid}";
            tooltip-format-ethernet = "{ipaddr}";
            tooltip-format-disconnected = "Disconnected";
            on-click = "rofi-network-manager";
          };

          "pulseaudio" = {
            format = "<span size='large'>{icon}</span> {volume}%";
            format-muted = "<span size='large'>󰝟</span> {volume}%";
            format-icons = {
              default = ["󰕿" "󰖀" "󰕾"];
              headphone = "󰋋";
              headset = "󰋎";
              bluetooth = "󰂯";
            };
            on-click = "easyeffects";
          };

          "hyprland/workspaces" = {
            format = "{name}";
            on-click = "activate";
          };

          "cpu" = {
            interval = 5;
            format = "<span size='large'>󰍛</span> {usage}%";
            max-length = 10;
          };

          "memory" = {
            interval = 10;
            format = "<span size='large'>󰘚</span> {used:0.1f}GB";
            tooltip-format = "Used: {used:0.1f}GB\nTotal: {total:0.1f}GB";
          };

          "custom/cputemp" = {
            interval = 5;
            exec = "sensors | awk '/CPU:/ {gsub(/[+°C]/,\"\",$2); print $2}'";
            format = "<span size='large'>󰔐</span> {}";
            tooltip = false;
          };

          "custom/gpu" = {
            interval = 5;
            exec = "cat /sys/class/hwmon/hwmon*/device/gpu_busy_percent 2>/dev/null || echo 'N/A'";
            format = "<span size='large'>󰢮</span> {}%";
            tooltip = false;
          };

          "custom/vram" = {
            interval = 5;
            exec = "cat /sys/class/hwmon/hwmon*/device/mem_info_vram_used 2>/dev/null | awk '{printf \"%.1f\", $1/1073741824}' || echo 'N/A'";
            format = "<span size='large'>󰆼</span> {}GB";
            tooltip = false;
          };

          "custom/gputemp" = {
            interval = 5;
            exec = "sensors | awk '/junction/ {gsub(/[+°C]/,\"\",$2); print $2}'";
            format = "<span size='large'>󰔏</span> {}°C";
            tooltip = false;
          };

          "custom/power" = {
            format = "<span size='large'>⏻</span>";
            on-click = "rofi -show power-menu -modi power-menu:rofi-power-menu --choices=lockscreen/logout/reboot/shutdown --confirm=reboot/shutdown";
            tooltip = false;
          };
        };
      };
      style = ''
        * {
          font-family: "SF Pro Nerd Font";
          font-size: 15px;
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

        #custom-power, #cpu, #memory, #custom-cputemp,
        #custom-gpu, #custom-vram, #custom-gputemp,
        #workspaces, #pulseaudio, #network, #clock {
          padding: 0 12px;
        }

        #workspaces button.active {
          background: #fff;
          color: #7e7e7e;
          border-radius: 8px;
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
          font-size: 13px;
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
