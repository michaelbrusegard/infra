{
  lib,
  pkgs,
  isWsl,
  homePersistenceRoot ? null,
  ...
}: {
  programs.thunderbird = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
    enable = true;
    package = pkgs.betterbird;
    profiles.default = {
      isDefault = true;
    };
  };

  home =
    {
      packages = lib.mkIf pkgs.stdenv.isDarwin [pkgs.brewCasks.betterbird];
    }
    // lib.optionalAttrs (pkgs.stdenv.isLinux && !isWsl && homePersistenceRoot != null) {
      persistence.${homePersistenceRoot}.directories = [
        ".thunderbird"
      ];
    };

  xdg.mimeApps.defaultApplications = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
    "x-scheme-handler/mailto" = ["betterbird.desktop"];
    "message/rfc822" = ["betterbird.desktop"];
  };
}
