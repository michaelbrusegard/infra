{pkgs, ...}: {
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
      package = pkgs.darwin.linux-builder-x86_64;
      config.virtualisation = {
        cores = 8;
        darwin-builder = {
          diskSize = 64 * 1024;
          memorySize = 16384;
        };
      };
      systems = ["x86_64-linux"];
      speedFactor = 2;
    };
  };
}
