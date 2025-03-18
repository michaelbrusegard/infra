{ pkgs, ... }: {
  environment = {
    systemPackages = with pkgs; [
      qemu
      wl-clipboard
      rofi-wayland
      mako
      libnotify
      swww
    ];
    sessionVariables = {
      WLR_NO_HARDWARE_CURSORS = "1";
      NIXOS_OZONE_WL = "1";
      XDG_CURRENT_DESKTOP = "hyprland";
      XDG_SESSION_TYPE = "wayland";
      XDG_SESSION_DESKTOP = "hyprland";
      QT_QPA_PLATFORM = "wayland";
      XDG_SCREENSHOTS_DIR = "$HOME/Pictures/Screenshots";
    };
  }
};
