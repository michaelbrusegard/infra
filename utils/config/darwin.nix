{ pkgs, userName, hostName, home-manager, sops-nix, ... }:
{
  imports = [
    home-manager.darwinModules.default
    sops-nix.darwinModules.sops
  ];
  nix = {
    settings = {
      allowed-users = ["@admin"];
      trusted-users = ["@admin"];
    };
    linux-builder.enable = true;
  };
  networking = {
    computerName = hostName;
    localHostName = hostName;
    dns = [
      "1.1.1.1"
      "1.0.0.1"
      "2606:4700:4700::1111"
      "2606:4700:4700::1001"
    ];
  };
  users.users.${userName} = {
    home = "/Users/${userName}";
    extraGroups = [ "admin" ];
  };
  sops.age.keyFile = "/Users/${userName}/.config/sops/age/keys.txt";
  security = {
    pam.enableSudoTouchIdAuth = true;
  };
  power = {
    sleep = {
      allowSleepByPowerButton = false;
      computer = "never";
      hardDisk = "never";
      display = 20;
    };
    restartAfterFreeze = true;
    restartAfterPowerFailure = true;
  };
}
