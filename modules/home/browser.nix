{
  pkgs,
  lib,
  isWsl,
  ...
}: {
  config = lib.mkIf (!isWsl) {
    programs.chromium = {
      enable = true;
      package = pkgs.brave;
    };
  };
}
