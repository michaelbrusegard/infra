{ userName, hostName, home-manager, nix-homebrew, dotfiles-private, ... }:
{
  imports = [
    dotfiles-private.darwinModules.secrets
    home-manager.darwinModules.default
    nix-homebrew.darwinModules.nix-homebrew
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
    linux-builder.enable = true;
  };
  networking = {
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
