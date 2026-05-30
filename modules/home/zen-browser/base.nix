{pkgs, ...}: {
  programs.zen-browser = {
    enable = true;
    darwinDefaultsId = "app.zen-browser.zen";
    setAsDefaultBrowser = pkgs.stdenv.isLinux;
  };
}
