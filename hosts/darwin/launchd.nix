{ pkgs, userName, ... }: {
  launchd.user.agents = {
    kanata = {
      command = "sudo ${pkgs.kanata}/bin/kanata --cfg ./kanata.kbd --nodelay";
      serviceConfig = {
        UserName = userName;
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
    podman = {
      command = "${pkgs.podman}/bin/podman system service --time=0";
      serviceConfig = {
        UserName = username;
        RunAtLoad = true;
        KeepAlive = true;
        StandardErrorPath = "/Users/${userName}/.logs/podman-error.log";
        StandardOutPath = "/Users/${userName}/.logs/podman-out.log";
        ProcessType = "Background";
      };
    };
  };
}

