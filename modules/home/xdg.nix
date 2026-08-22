{
  pkgs,
  isWsl,
  ...
}: {
  xdg = {
    enable = pkgs.stdenv.hostPlatform.isLinux;

    userDirs = {
      enable = pkgs.stdenv.hostPlatform.isLinux;
      createDirectories = true;
      # Keep exporting XDG_*_DIR env vars (26.05 default flips to false).
      setSessionVariables = true;

      desktop = "$HOME/Desktop";
      documents = "$HOME/Documents";
      download = "$HOME/Downloads";
      pictures = "$HOME/Pictures";
      videos = "$HOME/Videos";
      projects = "$HOME/Projects";

      extraConfig = {
        SCREENSHOTS = "$HOME/Pictures/screenshots";
      };
    };

    mimeApps.enable = pkgs.stdenv.hostPlatform.isLinux && !isWsl;
  };
}
