{ ... }:

{
  imports = [
    ../common/nix.nix
  ];
  nix = {
    gc.dates = "weekly";
    daemonCPUSchedPolicy = "idle";
    daemonIOSchedClass = "idle";
    settings = {
      allowed-users = [ "@wheel" ];
      trusted-users = [ "@wheel" ];
    };
  };
  users.mutableUsers = false;
}
