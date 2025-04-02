{ userName, pkgs, system, ... }: {
  programs = {
    dconf.enable = true;
    regreet = {
      enable = true;
      font = {
        name = "SF Pro";
      };
      theme = {
        name = "Catppuccin-Mocha-Standard-Blue-Dark";
        package = pkgs.catppuccin-gtk;
      };
      settings = {
        background = {
          path = ../../assets/wallpapers/twilight-peaks.png;
          fit = "Cover";
        };
        appearance = {
          greeting_msg = "Authenticating into Desktop";
        };
        "widget.clock" = {
          format = "%A %-d %B %H:%M";
          timezone = "Europe/Oslo";
          label_width = 200;
        };
      };
    };
  };
}
