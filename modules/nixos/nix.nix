_: {
  imports = [
    ../common/nix.nix
  ];
  nix = {
    daemonCPUSchedPolicy = "idle";
    daemonIOSchedClass = "idle";
    settings = {
      allowed-users = ["@wheel"];
      trusted-users = ["@wheel"];
    };
  };
  users.mutableUsers = false;
}
