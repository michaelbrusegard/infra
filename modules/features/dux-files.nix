{ inputs, ... }: {
  flake.modules.homeManager.dux-files =
    {
      pkgs,
      lib,
      homePersistenceRoot ? null,
      ...
    }:
    {
      imports = [
        inputs.dux-files.homeModules.default
      ];

      programs.dux-files = {
        enable = true;
        package = pkgs.dux-files;
        systemd.enable = true;
      };

      home = lib.optionalAttrs (homePersistenceRoot != null) {
        persistence.${homePersistenceRoot}.directories = [
          ".config/dfiles"
          ".local/state/dfiles"
        ];
      };

      xdg.mimeApps.defaultApplications = {
        "inode/directory" = [ "dev.duxlabs.files.desktop" ];
      };
    };
}
