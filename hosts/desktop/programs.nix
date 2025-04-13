{ pkgs, ... }: {
  programs = {
    dconf.enable = true;
    hyprland = {
      enable = true;
      withUWSM = true;
    };
    regreet = {
      enable = true;
      font = {
        name = "SF Pro";
      };
      theme = {
        name = "Adwaita-dark";
        package = pkgs.gnome-themes-extra;
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
