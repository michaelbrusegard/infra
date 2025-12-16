{ config, lib, pkgs-unstable, isDarwin, ... }:

let
  cfg = config.modules.freecad;
in {
  options.modules.freecad.enable = lib.mkEnableOption "FreeCAD Configuration";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs-unstable; lib.optionals (!isDarwin) [
      freecad-wayland
    ];

    home.file = lib.mkMerge [
      (lib.mkIf isDarwin {
        "Library/Preferences/FreeCAD".source = config.lib.file.mkOutOfStoreSymlink ./config;
        "Library/Application Support/FreeCAD/Macro".source = config.lib.file.mkOutOfStoreSymlink ./share/Macro;
      })
      (lib.mkIf (!isDarwin) {
        ".config/FreeCAD".source = config.lib.file.mkOutOfStoreSymlink ./config;
        ".local/share/FreeCAD/Macro".source = config.lib.file.mkOutOfStoreSymlink ./share/Macro;
      })
    ];
  };
}
