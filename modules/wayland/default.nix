{ config, lib, pkgs, ... }:

let
  cfg = config.modules.wayland;
in {
  imports = [
    # ./hypridle.nix
    ./hyprland.nix
    # ./hyprlock.nix
    ./hyprpaper.nix
    ./rofi.nix
    # ./waybar.nix
  ];
  options.modules.wayland.enable = lib.mkEnableOption "Wayland configuration";

  config = lib.mkIf cfg.enable {
    gtk = {
      enable = true;
      theme = {
        name = "Catppuccin-GTK-Dark";
        package = pkgs.magnetic-catppuccin-gtk;
      };
      iconTheme = {
        name = "Papirus-Dark";
        package = pkgs.papirus-icon-theme;
      };
      font.name = "SF Pro";
    };
    qt = {
      enable = true;
      style = {
        name = "catppuccin-mocha-blue";
        package = pkgs.catppuccin-qt5ct;
      };
    };
    services.playerctld.enable = true;
    home.packages = with pkgs; [
      wl-clipboard
      cliphist
      mako
      libnotify
      hyprpicker
    ];
    catppuccin.mako = {
      enable = true;
      accent = "blue";
    };
  };
}
