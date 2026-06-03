{
  pkgs,
  lib,
  config,
  isWsl,
  homePersistenceRoot ? null,
  ...
}: let
  dmsConfig = "${config.home.homeDirectory}/Projects/infra/config/dms";
in {
  home =
    {
      sessionVariables = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
        ELECTRON_OZONE_PLATFORM_HINT = "auto";
        GTK_THEME = "Catppuccin-GTK-Dark";
      };

      pointerCursor = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
        package = pkgs.bibata-cursors;
        name = "Bibata-Modern-Classic";
        size = 24;
        gtk.enable = true;
        x11.enable = true;
        hyprcursor.enable = true;
      };
    }
    // lib.optionalAttrs (homePersistenceRoot != null) {
      persistence.${homePersistenceRoot}.directories = [
        ".local/state/DankMaterialShell"
        ".cache/DankMaterialShell"
      ];
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
        general = "Google Sans Flex,11";
        fixed = "GoogleSansCode Nerd Font,11";
      };
    })));

  gtk = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
    enable = true;
    colorScheme = "dark";

    theme = {
      name = "Catppuccin-GTK-Dark";
      package = pkgs.magnetic-catppuccin-gtk;
    };

    # Keep applying the GTK3 theme to GTK4 apps (26.05 default flips to null).
    gtk4.theme = {
      name = "Catppuccin-GTK-Dark";
      package = pkgs.magnetic-catppuccin-gtk;
    };

    iconTheme = {
      name = "Papirus-Dark";
      package = lib.mkForce (pkgs.catppuccin-papirus-folders.override {
        inherit (config.catppuccin) accent flavor;
      });
    };

    font = {
      name = "Google Sans Flex";
      size = 11;
      package = pkgs.google-sans-flex;
    };
  };

  xdg.configFile = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
    "DankMaterialShell".source = config.lib.file.mkOutOfStoreSymlink dmsConfig;
  };
}
