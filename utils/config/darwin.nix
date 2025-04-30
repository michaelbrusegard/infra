{ userName, hostName, home-manager, dotfiles-private, ... }:
{
  imports = [
    dotfiles-private.darwinModules.secrets
    home-manager.darwinModules.default
  ];
  nix = {
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
    restartAfterPowerFailure = true;
  };
}
