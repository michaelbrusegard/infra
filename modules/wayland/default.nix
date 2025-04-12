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
        name = "WhiteSur-Dark";
        package = pkgs.whitesur-gtk-theme;
      };
      iconTheme = {
        name = "WhiteSur";
        package = pkgs.whitesur-icon-theme;
      };
      font.name = "SF Pro";
    };
    qt = {
      enable = true;
      style = {
        name = "WhiteSur-Dark";
        package = pkgs.whitesur-qt5ct;
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
