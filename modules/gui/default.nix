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
    ] 
    ++ (lib.optionals isDarwin [
      raycast
      ice-bar
    ])
    ++ (lib.optionals (!isDarwin) [
      element-desktop
      legcord
      obsidian
      nix-proton.packages.${system}.proton-mail-desktop
      nix-proton.packages.${system}.proton-pass-desktop
      protonvpn-gui
      davinci-resolve
    ]);
  };
}
