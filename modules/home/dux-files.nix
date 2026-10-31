{
  pkgs,
  lib,
  inputs,
  isWsl,
  homePersistenceRoot ? null,
  ...
}: let
  enable = pkgs.stdenv.hostPlatform.isLinux && !isWsl;
in {
  imports = [
    inputs.dux-files.homeModules.default
  ];

  programs.dux-files = {
    inherit enable;
    package = pkgs.dux-files;
    systemd.enable = true;
  };

  home = lib.optionalAttrs (homePersistenceRoot != null) {
    persistence.${homePersistenceRoot}.directories = [
      ".config/dfiles"
      ".local/state/dfiles"
    ];
  };

  xdg.mimeApps.defaultApplications = lib.mkIf enable {
    "inode/directory" = ["dev.duxlabs.files.desktop"];
  };
}
