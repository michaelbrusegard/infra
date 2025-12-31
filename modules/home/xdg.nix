{
  pkgs,
  lib,
  ...
}: {
  xdg = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;

    userDirs = {
      enable = true;
      createDirectories = true;

      desktop = "$HOME/Desktop";
      documents = "$HOME/Documents";
      download = "$HOME/Downloads";
      pictures = "$HOME/Pictures";
      videos = "$HOME/Movies";

      extraConfig = {
        XDG_PROJECTS_DIR = "$HOME/Projects";
        XDG_SCREENSHOTS_DIR = "$HOME/Pictures/screenshots";
      };
    };

    mimeApps = {
      enable = true;
      defaultApplications = {
        "application/pdf" = ["org.pwmt.zathura.desktop"];
        "image/png" = ["imv.desktop"];
        "image/jpeg" = ["imv.desktop"];
        "video/mp4" = ["mpv.desktop"];
      };
    };
  };
}
