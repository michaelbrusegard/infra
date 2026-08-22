{
  lib,
  pkgs,
  isWsl,
  homePersistenceRoot ? null,
  ...
}: {
  programs.thunderbird = lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && !isWsl) {
    enable = true;
    package = pkgs.betterbird;
    profiles.default = {
      isDefault = true;
    };
  };

  home =
    {
      packages = lib.optionals (pkgs.stdenv.hostPlatform.isDarwin && pkgs.brewCasks ? betterbird) [
        pkgs.brewCasks.betterbird
      ];
    }
    // lib.optionalAttrs (pkgs.stdenv.hostPlatform.isLinux && !isWsl && homePersistenceRoot != null) {
      persistence.${homePersistenceRoot}.directories = [
        ".thunderbird"
      ];
    };

  xdg.mimeApps.defaultApplications = lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && !isWsl) {
    "x-scheme-handler/mailto" = ["betterbird.desktop"];
    "message/rfc822" = ["betterbird.desktop"];
  };
}
