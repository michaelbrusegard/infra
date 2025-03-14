{ pkgs, username, ... }: {
  launchd.user.agents.kanata = {
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
}

