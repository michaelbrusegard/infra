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
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 24;
      gtk.enable = true;
      x11.enable = true;
      hyprcursor.enable = true;
    };
  };

  qt = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) ({
      enable = true;
      style.name = "kvantum";
    }
    // (lib.genAttrs ["qt5ctSettings" "qt6ctSettings"] (_: {
      Appearance = {
        style = "kvantum";
        icon_theme = "Papirus-Dark";
        standard_dialogs = "xdgdesktopportal";
      };

      Fonts = {
        general = "RobotoMono Nerd Font,11";
        fixed = "RobotoMono Nerd Font,11";
      };
    })));

  gtk = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
    enable = true;

    theme = {
      name = "Catppuccin-BL-MB-dark";
      package = pkgs.magnetic-catppuccin-gtk;
    };

    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.catppuccin-papirus-folders.override {
        inherit (config.catppuccin) accent flavor;
      };
    };

    font = {
      name = "RobotoMono Nerd Font";
      size = 11;
    };
  };

  home.packages = with pkgs;
    lib.optionals (stdenv.isLinux && !isWsl) [
      kvantum
      kvantum-qt5
      kvantum-qt6
    ];

  xdg.configFile = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
    "DankMaterialShell".source = config.lib.file.mkOutOfStoreSymlink dmsConfig;
  };
}
