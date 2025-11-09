{ config, lib, pkgs, ... }:

let
  cfg = config.modules.wayland;
in {
  imports = [
    ./dank-material-shell.nix
    ./hyprland.nix
  ];
  options.modules.wayland.enable = lib.mkEnableOption "Wayland configuration";

  config = lib.mkIf cfg.enable {
    # gtk = {
    #   enable = true;
    #   theme = {
    #     name = "Adwaita-dark";
    #     package = pkgs.gnome-themes-extra;
    #   };
    #   iconTheme = {
    #     name = "Papirus-Dark";
    #     package = pkgs.papirus-icon-theme;
    #   };
    #   font.name = "SFPro";
    # };
    # qt = {
    #   enable = true;
    #   style = {
    #     name = "adwaita-dark";
    #     package = pkgs.adwaita-qt;
    #   };
    # };
    # dconf.settings."org/gnome/desktop/interface" = {
    #   color-scheme = "prefer-dark";
    # };
    services.cliphist.enable = true;
    home = {
      packages = with pkgs; [
        libGL
        libxkbcommon
        pciutils
        wl-clipboard
        cava
        polkit_gnome
        grim
        slurp
        wf-recorder
      ];
      sessionVariables = {
        LD_LIBRARY_PATH = lib.makeLibraryPath [
          pkgs.libGL
          pkgs.libxkbcommon
          pkgs.wayland
        ];
        QT_QPA_PLATFORM = "wayland";
        ELECTRON_OZONE_PLATFORM_HINT = "auto";
        QT_QPA_PLATFORMTHEME = "gtk3";
        QT_QPA_PLATFORMTHEME_QT6 = "gtk3";
      };
    };
  };
}
