{ userName, pkgs, system, apple-fonts, ... }: {
  programs = {
    dconf.enable = true;
    regreet = {
      enable = true;
      cursorTheme = {
        name = "macOS";
        package = pkgs.apple-cursor;
      };
      font = {
        name = "SF Pro";
        package = apple-fonts.packages.${system}.sf-pro;
      };
      theme = {
        name = "Adwaita-dark";
        package = pkgs.gnome.adwaita-dark-theme;
      };
      iconTheme = {
        name = "Adwaita-dark";
        package = pkgs.gnome3.adwaita-dark-icon-theme;
      };
      settings = {
        background = {
          path = "/home/${userName}/Developer/dotfiles/assets/wallpapers/twilight-peaks.png";
          fit = "Cover";
        };
        appearance = {
          greeting_msg = "Welcome";
        };
        "widget.clock" = {
          format = "%A %e %b %H:%M";
          timezone = "Europe/Oslo";
          label_width = 200;
        };
      };
    };
  };
}
