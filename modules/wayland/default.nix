{ config, lib, pkgs, ... }:

let
  cfg = config.modules.wayland;
in {
  imports = [
    ./hypridle.nix
    ./hyprland.nix
    ./hyprlock.nix
    ./hyprpaper.nix
    ./mako.nix
    ./rofi.nix
    ./waybar.nix
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
        name = "Papirus-Dark";
        package = pkgs.papirus-icon-theme;
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
    systemd.user.services.wl-clip-persist = {
      Unit.PartOf = ["graphical-session.target"];
      Service = {
        ExecStart = "${pkgs.wl-clip-persist}/bin/wl-clip-persist --clipboard both";
        Restart = "always";
      };
      Install.WantedBy = ["graphical-session.target"];
    };
    home = {
      packages = with pkgs; [
        libGL
        libxkbcommon
        wl-clipboard
        hyprpicker
        grim
        slurp
      ];
      sessionVariables = {
        LD_LIBRARY_PATH = "${pkgs.libGL}/lib:${pkgs.libxkbcommon}/lib:${pkgs.wayland}/lib";
        NIXOS_OZONE_WL = "1";
      };
      file.".local/share/applications/hyprpicker.desktop".text = ''
        [Desktop Entry]
        Name=Hyprpicker
        Exec=hyprpicker -a
        Type=Application
        Categories=Utility;
      '';
    };
  };
}
