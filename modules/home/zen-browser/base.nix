{
  pkgs,
  lib,
  homePersistenceRoot ? null,
  ...
}: {
  programs.zen-browser = {
    enable = true;
    darwinDefaultsId = "app.zen-browser.zen";
    setAsDefaultBrowser = pkgs.stdenv.hostPlatform.isLinux;
  };

  home = lib.optionalAttrs (homePersistenceRoot != null) {
    persistence.${homePersistenceRoot}.directories = [
      ".config/zen"
    ];
  };
}
