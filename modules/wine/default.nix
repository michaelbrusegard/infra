{ config, lib, pkgs, ... }:

let
  cfg = config.modules.wine;
in {
  options.modules.wine.enable = lib.mkEnableOption "Wine configuration";

  # Guide for affinity software on linux for later
  # https://github.com/22-pacific/Affinity-Linux/blob/main/Manual%20Guide.md
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      wineWowPackages.waylandFull
    ];
  };
}
