{ pkgs, config, userName, ... }: {
  launchd = {
    daemons = {
      kanata = {
        command = "${pkgs.kanata}/bin/kanata -c ${./kanata.kbd}";
        serviceConfig = {
          RunAtLoad = true;
          KeepAlive = true;
          StandardErrorPath = "/Library/Logs/Kanata/kanata.err.log";
          StandardOutPath = "/Library/Logs/Kanata/kanata.out.log";
        };
      };
      karabiner-vhiddaemon = {
        serviceConfig = {
          ProgramArguments = [
            "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
          ];
          RunAtLoad = true;
          KeepAlive = true;
        };
      };
      karabiner-vhidmanager = {
        serviceConfig = {
          ProgramArguments = [
            "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"
            "activate"
          ];
          RunAtLoad = true;
        };
      };
    };
    user.agents = {
      colima = {
        command = "${pkgs.colima}/bin/colima start --cpu 4 --memory 8 --disk 100 --arch x86_64 --vm-type vz --vz-rosetta --mount-type virtiofs";
        serviceConfig = {
          EnvironmentVariables = {
            PATH = "${pkgs.docker}/bin:${pkgs.colima}/bin:/usr/local/bin:/usr/bin:/bin";
          };
          RunAtLoad = true;
          KeepAlive = true;
          StandardErrorPath = "${config.users.users.${userName}.home}/Library/Logs/Colima/colima.err.log";
          StandardOutPath = "${config.users.users.${userName}.home}/Library/Logs/Colima/colima.out.log";
        };
      };
      docker-auto-prune = {
        command = "${pkgs.docker}/bin/docker system prune -af";
        serviceConfig = {
          UserName = userName;
          StartCalendarInterval = {
            Weekday = 0;
            Hour = 3;
            Minute = 0;
          };
          StandardErrorPath = "${config.users.users.${userName}.home}/Library/Logs/Docker/docker-prune.err.log";
          StandardOutPath = "${config.users.users.${userName}.home}/Library/Logs/Docker/docker-prune.out.log";
        };
      };
      raycast = {
        command = "open -a Raycast";
        serviceConfig = {
          UserName = userName;
          RunAtLoad = true;
          ProcessType = "Interactive";
        };
      };
      ice = {
        command = "open -a Ice";
        serviceConfig = {
          UserName = userName;
          RunAtLoad = true;
          ProcessType = "Interactive";
        };
      };
      linearmouse = {
        command = "open -a LinearMouse";
        serviceConfig = {
          UserName = userName;
          RunAtLoad = true;
          ProcessType = "Interactive";
        };
      };
      aldente = {
        command = "open -a AlDente";
        serviceConfig = {
          UserName = userName;
          RunAtLoad = true;
          ProcessType = "Interactive";
        };
      };
    };
  };
}
