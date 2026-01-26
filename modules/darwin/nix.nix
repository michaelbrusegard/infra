_: {
  imports = [
    ../common/nix.nix
  ];
  nix = {
    gc.interval = {
      Weekday = 0;
      Hour = 0;
      Minute = 0;
    };
    settings = {
      allowed-users = ["@admin"];
      trusted-users = ["@admin"];
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
}
