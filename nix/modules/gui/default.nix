{ config, lib, pkgs, isDarwin, ... }:

let
  cfg = config.modules.gui;
in {
  options.modules.gui.enable = lib.mkEnableOption "GUI applications";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      transmission_4
      slack
      zoom-us
    ] 
    ++ (lib.optionals isDarwin [
      raycast
    ])
    ++ (lib.optionals (!isDarwin) [
      element-desktop
      legcord
      obsidian
      protonmail-desktop
      proton-pass
      protonvpn-gui
    ]);
  };
}
