{ config, lib, pkgs, ... }:

let
  cfg = config.modules.wayland;
  clipsync = pkgs.writeShellApplication {
    name = "clipsync";
    text = builtins.readFile ./config/clipsync.sh;
    runtimeInputs = with pkgs; [
      wl-clipboard
      xclip
      clipnotify
      libnotify
    ];
  };
in {
  imports = [
    ./hypridle.nix
    ./hyprland.nix
    ./hyprlock.nix
    ./hyprpaper.nix
    ./mako.nix
    ./rofi.nix
    # ./waybar.nix
  ];
  options.modules.wayland.enable = lib.mkEnableOption "Wayland configuration";

  config = lib.mkIf cfg.enable {
    gtk = {
      enable = true;
      theme = {
        name = "Adwaita-dark";
        package = pkgs.gnome-themes-extra;
      };
      iconTheme = {
        name = "Adwaita";
        package = pkgs.adwaita-icon-theme;
      };
      font.name = "SF Pro";
    };
    qt = {
      enable = true;
      style = {
        name = "adwaita-dark";
        package = pkgs.adwaita-qt;
      };
    };
    services = { 
      cliphist.enable = true;
      playerctld.enable = true;
    };
    systemd.user.services.clipsync = {
      Unit.PartOf = "graphical-session.target";
      Service = {
        ExecStart = "${clipsync}/bin/clipsync watch with-notifications";
        ExecStop = "${clipsync}/bin/clipsync stop";
        Restart = "always";
      };
      Install.WantedBy = ["graphical-session.target"];
    };
    home.packages = with pkgs; [
      hyprpicker
    ];
  };
}
