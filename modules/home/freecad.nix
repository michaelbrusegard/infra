{
  pkgs,
  lib,
  config,
  isWsl,
  homePersistenceRoot ? null,
  ...
}: let
  freecadConfig = "${config.home.homeDirectory}/Projects/infra/config/freecad";
in
  {
    home.packages =
      lib.optionals (pkgs.stdenv.isLinux && !isWsl) [
        pkgs.freecad-wayland
      ]
      ++ lib.optionals pkgs.stdenv.isDarwin [
        pkgs.brewCasks.freecad
      ];

    home.file = lib.mkMerge [
      (lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
        ".config/FreeCAD".source =
          config.lib.file.mkOutOfStoreSymlink freecadConfig;

        ".local/share/FreeCAD/v1-1/Macro".source =
          config.lib.file.mkOutOfStoreSymlink "${freecadConfig}/v1-1/macros";
      })

      (lib.mkIf pkgs.stdenv.isDarwin {
        "Library/Preferences/FreeCAD".source =
          config.lib.file.mkOutOfStoreSymlink freecadConfig;

        "Library/Application Support/FreeCAD/Macro".source =
          config.lib.file.mkOutOfStoreSymlink "${freecadConfig}/macros";
      })
    ];
  }
  // lib.optionalAttrs (homePersistenceRoot != null) {
    home.persistence.${homePersistenceRoot}.directories = [
      ".local/share/FreeCAD/v1-1/Mod"
    ];
  }
