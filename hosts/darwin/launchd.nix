{ pkgs, userName, ... }: {
  launchd = {
    daemons = {
      kanata = {
        command = "${pkgs.kanata}/bin/kanata --cfg ${./kanata.kbd} --nodelay";
        serviceConfig = {
          RunAtLoad = true;
          KeepAlive = {
            SuccessfulExit = false;
            Crashed = true;
          };
          StandardErrorPath = "/Users/${userName}/.logs/kanata-error.log";
          StandardOutPath = "/Users/${userName}/.logs/kanata-out.log";
          ProcessType = "Interactive";
          Nice = -30;
        };
      };
    };
    user.agents = {
      raycast = {
        command = "open -a Raycast";
        serviceConfig = {
          UserName = userName;
          RunAtLoad = true;
          KeepAlive = false;
          ProcessType = "Interactive";
        };
      };
      ice = {
        command = "open -a Ice";
        serviceConfig = {
          UserName = userName;
          RunAtLoad = true;
          KeepAlive = false;
          ProcessType = "Interactive";
        };
      };
      podman = {
        command = "${pkgs.podman}/bin/podman machine start";
        serviceConfig = {
          UserName = userName;
          RunAtLoad = true;
          KeepAlive = true;
          StandardErrorPath = "/Users/${userName}/.logs/podman-error.log";
          StandardOutPath = "/Users/${userName}/.logs/podman-out.log";
          ProcessType = "Background";
        };
      };
    };
  };
}
