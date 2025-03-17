{ pkgs, username, ... }: {
  launchd.user.agents = {
    kanata = {
      command = "sudo ${pkgs.kanata}/bin/kanata --cfg ./kanata.kbd --nodelay";
      serviceConfig = {
        UserName = username;
        RunAtLoad = true;
        KeepAlive = {
          SuccessfulExit = false;
          Crashed = true;
        };
        StandardErrorPath = "/Users/${username}/.logs/kanata-error.log";
        StandardOutPath = "/Users/${username}/.logs/kanata-out.log";
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
        StandardErrorPath = "/Users/${username}/.logs/podman-error.log";
        StandardOutPath = "/Users/${username}/.logs/podman-out.log";
        ProcessType = "Background";
      };
    };
  };
}

