{ pkgs, lib, inputs, isWsl, ... }:

let
  freecadConfig = inputs.self + "/config/freecad";
in
{
  home.packages =
    lib.optionals (pkgs.stdenv.isLinux && !isWsl) [
      pkgs.freecad-wayland
    ];

  home.file =
    lib.mkMerge [
      (lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
        ".config/FreeCAD".source =
          lib.file.mkOutOfStoreSymlink freecadConfig;

        ".local/share/FreeCAD/Macro".source =
          lib.file.mkOutOfStoreSymlink "${freecadConfig}/macros";
      })

      (lib.mkIf pkgs.stdenv.isDarwin {
        "Library/Preferences/FreeCAD".source =
          lib.file.mkOutOfStoreSymlink freecadConfig;

        "Library/Application Support/FreeCAD/Macro".source =
          lib.file.mkOutOfStoreSymlink "${freecadConfig}/macros";
      })
    ];
}
