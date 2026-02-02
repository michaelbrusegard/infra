{
  lib,
  isWsl,
  ...
}: {
  programs.zathura = lib.mkIf (!isWsl) {
    enable = true;
    options = {
      selection-clipboard = "clipboard";
    };
  };

  xdg.mimeApps.defaultApplications = lib.mkIf (!isWsl) {
    "application/pdf" = ["org.pwmt.zathura.desktop"];
  };
}
