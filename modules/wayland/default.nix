{ config, lib, pkgs, hyprland, apple-fonts, system, ... }:

let
  cfg = config.modules.wayland;
in {
  imports = [
    ./hypridle.nix
    ./hyprland.nix
    ./hyprlock.nix
    ./hyprpaper.nix
    ./rofi.nix
    ./waybar.nix
  ];
  options.modules.wayland.enable = lib.mkEnableOption "Wayland configuration";

  config = lib.mkIf cfg.enable {
    gtk = {
      enable = true;
      font = {
        name = "SF Pro";
        package = apple-fonts.packages.${system}.sf-pro;
      };
    };
    qt = {
      enable = true;
      style.name = "adwaita-dark";
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
