{
  lib,
  pkgs,
  isWsl,
  homePersistenceRoot ? null,
  ...
}: {
  programs.thunderbird = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
    enable = true;
    profiles.default = {
      isDefault = true;
    };
  };

  home =
    {
      packages = lib.mkIf pkgs.stdenv.isDarwin [pkgs.brewCasks.thunderbird];
    }
    // lib.optionalAttrs (pkgs.stdenv.isLinux && !isWsl && homePersistenceRoot != null) {
      persistence.${homePersistenceRoot}.directories = [
        ".thunderbird"
      ];
    };

  xdg.mimeApps.defaultApplications = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
    "x-scheme-handler/mailto" = ["thunderbird.desktop"];
    "message/rfc822" = ["thunderbird.desktop"];
  };
}
