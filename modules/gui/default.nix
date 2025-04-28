{ config, lib, pkgs, isDarwin, nix-proton, system, ... }:

let
  cfg = config.modules.gui;
in {
  options.modules.gui.enable = lib.mkEnableOption "GUI applications";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      transmission_4
      slack
      zoom-us
      gimp-with-plugins
      inkscape-with-extensions
    ]
    ++ (lib.optionals isDarwin [
      raycast
      ice-bar
    ])
    ++ (lib.optionals (!isDarwin) [
      easyeffects
      element-desktop
      legcord
      obsidian
      nix-proton.packages.${system}.proton-mail-desktop
      nix-proton.packages.${system}.proton-pass-desktop
      davinci-resolve
    ]);
  };
}
