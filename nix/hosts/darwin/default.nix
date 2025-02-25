{ ... }: {
  system.stateVersion = 5;
  nix = {
    daemonCPUSchedPolicy = "idle";
    daemonIOSchedClass = "idle";
    gc = {
      automatic = true;
      interval.Day = 7;
      options = "--delete-older-than 7d";
    };
    settings = {
      auto-optimise-store = true;
      builders-use-substitutes = true;
      allowed-users = ["@admin"];
      trusted-users = ["@admin"];
      extra-experimental-features = [ "flakes" "nix-command" ];
    };
  };
  nixpkgs.config = {
    allowUnfree = true;
    allowBroken = true;
  };
  imports = [
    ./system.nix
  ];
}
