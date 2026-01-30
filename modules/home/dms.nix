{
  pkgs,
  lib,
  config,
  isWsl,
  ...
}: let
  dmsConfig = "${config.home.homeDirectory}/Projects/nix-config/config/dms";
in {
  home = {
    sessionVariables = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
      ELECTRON_OZONE_PLATFORM_HINT = "auto";
    };

    pointerCursor = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
      package = pkgs.apple-cursor;
      name = "macOS";
      size = 24;
      gtk.enable = true;
      x11.enable = true;
      hyprcursor.enable = true;
    };

    file.".config/Kvantum/kvantum.kvconfig" = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
      text = ''
        [General]
        theme=Catppuccin-Mocha
      '';
    };
  };

  qt = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
    enable = true;

    qt5ctSettings = {
      Appearance = {
        style = "kvantum";
        icon_theme = "Papirus-Dark";
        standard_dialogs = "xdgdesktopportal";
      };

      Fonts = {
        general = "SFPro Nerd Font,11";
        fixed = "SFMono Nerd Font,11";
      };
    };
    qt6ctSettings = {
      Appearance = {
        style = "kvantum";
        icon_theme = "Papirus-Dark";
        standard_dialogs = "xdgdesktopportal";
      };
      Fonts = {
        general = "SFPro Nerd Font,11";
        fixed = "SFMono Nerd Font,11";
      };
    };
  };

  gtk = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
    enable = true;

    theme = {
      name = "Catppuccin-Mocha-Standard-Blue-Dark";
      package = pkgs.catppuccin-gtk;
    };

    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };

    font = {
      name = "SFPro Nerd Font";
      size = 11;
    };

    cursorTheme = {
      name = "macOS";
      size = 24;
    };
  };

  home.packages = with pkgs;
    lib.optionals (stdenv.isLinux && !isWsl) [
      kvantum
      kvantum-qt5
      kvantum-qt6
      papirus-icon-theme
      catppuccin-kvantum
    ];

  xdg.configFile = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
    "DankMaterialShell".source = config.lib.file.mkOutOfStoreSymlink dmsConfig;
  };
}
