{ config, pkgs, apple-fonts, ... }: {
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
        package = apple-fonts.packages.${config.system}.sf-pro;
      };
      settings = {
        background = {
          path = "${config.home.homeDirectory}/Developer/dotfiles/assets/wallpapers/twillight-peaks.png";
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
