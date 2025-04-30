{ pkgs, userName, ... }: {
  launchd.user.agents = {
    kanata = {
      command = "${pkgs.kanata}/bin/kanata --cfg ${./kanata.kbd} --nodelay";
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
      command = "${pkgs.podman}/bin/podman system service";
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
}
