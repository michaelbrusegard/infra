{pkgs, ...}: {
  xdg = {
    enable = pkgs.stdenv.isLinux;

    userDirs = {
      enable = pkgs.stdenv.isLinux;
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

    mimeApps.enable = pkgs.stdenv.isLinux;
  };
}
