{ pkgs, ... }: {
  environment = {
    systemPackages = with pkgs; [
      qemu
      wl-clipboard
      rofi-wayland
      mako
      libnotify
    ];
    sessionVariables = {
      WLR_NO_HARDWARE_CURSORS = "1";
      NIXOS_OZONE_WL = "1";"
    };
  }
};
