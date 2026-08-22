{
  lib,
  pkgs,
  isWsl,
  ...
}: let
  enable = pkgs.stdenv.hostPlatform.isLinux && !isWsl;
in {
  programs.zathura = lib.mkIf enable {
    enable = true;
    options = {
      selection-clipboard = "clipboard";
    };
  };

  xdg.mimeApps.defaultApplications = lib.mkIf enable {
    "application/pdf" = ["org.pwmt.zathura.desktop"];
  };
}
