{pkgs, ...}: {
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-termfilechooser
      pkgs.kdePackages.xdg-desktop-portal-kde
    ];

    config.common = {
      default = ["hyprland" "kde"];
      "org.freedesktop.impl.portal.FileChooser" = ["termfilechooser"];
    };
  };

  environment.systemPackages = with pkgs; [
    yazi
    wezterm
  ];

  environment.etc."xdg/xdg-desktop-portal-termfilechooser/config".text = ''
    [filechooser]
    cmd=yazi-wrapper.sh
    default_dir=$HOME
    env=TERMCMD=${pkgs.wezterm}/bin/wezterm start --class termfilechooser --always-new-process
  '';
}
