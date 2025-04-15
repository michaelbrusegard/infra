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
      Unit = {
        After = ["graphical-session.target"];
        PartOf = "graphical-session.target";
      };
      Service = {
        Type = "simple";
        Environment = [
          "WAYLAND_DISPLAY=wayland-1"
          "DISPLAY=:0"
        ];
        ExecStart = "${clipsync}/bin/clipsync watch";
        ExecStop = "${clipsync}/bin/clipsync stop";
        Restart = "on-failure";
        RestartSec = "1s";
      };
      Install.WantedBy = ["graphical-session.target"];
    };
    home.packages = with pkgs; [
      hyprpicker
    ];
  };
}
