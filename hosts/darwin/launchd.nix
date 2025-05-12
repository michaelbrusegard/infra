{ pkgs, userName, ... }: {
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
    };
  };
}
