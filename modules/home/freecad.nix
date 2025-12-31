{
  pkgs,
  lib,
  config,
  inputs,
  isWsl,
  ...
}: let
  freecadConfig = inputs.self + "/config/freecad";
in {
  home.packages =
    lib.optionals (pkgs.stdenv.isLinux && !isWsl) [
      pkgs.freecad-wayland
    ]
    ++ lib.optionals (pkgs.stdenv.isDarwin) [
      pkgs.brewCasks.freecad
    ];

  home.file = lib.mkMerge [
    (lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
      ".config/FreeCAD".source =
        config.lib.file.mkOutOfStoreSymlink freecadConfig;

      ".local/share/FreeCAD/Macro".source =
        config.lib.file.mkOutOfStoreSymlink "${freecadConfig}/macros";
    })

    (lib.mkIf pkgs.stdenv.isDarwin {
      "Library/Preferences/FreeCAD".source =
        config.lib.file.mkOutOfStoreSymlink freecadConfig;

      "Library/Application Support/FreeCAD/Macro".source =
        config.lib.file.mkOutOfStoreSymlink "${freecadConfig}/macros";
    })
  ];
}
