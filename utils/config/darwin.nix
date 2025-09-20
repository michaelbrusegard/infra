{ userName, hostName, home-manager, mac-app-util, nix-homebrew, dotfiles-private, ... }:
{
  imports = [
    dotfiles-private.darwinModules.secrets
    home-manager.darwinModules.default
    nix-homebrew.darwinModules.nix-homebrew
    mac-app-util.darwinModules.default
  ];
  nix = {
    gc.interval = {
      Weekday = 0;
      Hour = 0;
      Minute = 0;
    };
    settings = {
      allowed-users = [ "@admin" ];
      trusted-users = [ "@admin" ];
    };
    linux-builder = {
      enable = true;
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      maxJobs = 8;
      speedFactor = 2;
    };
  };
  system.stateVersion = 5;
  networking = {
    applicationFirewall.enable = true;
    computerName = hostName;
    localHostName = hostName;
  };
  users.users.${userName} = {
    home = "/Users/${userName}";
  };
  power = {
    sleep = {
      allowSleepByPowerButton = false;
      computer = "never";
      harddisk = "never";
      display = 20;
    };
    restartAfterFreeze = true;
  };
}
