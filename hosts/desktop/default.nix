{ ... }: {
  imports = [
    ./boot.nix
    ./console.nix
    ./environment.nix
    ./file-systems.nix
    ./fonts.nix
    ./gtk.nix
    ./hardware.nix
    ./location.nix
    ./networking.nix
    ./programs.nix
    ./qt.nix
    ./security.nix
    ./services.nix
    ./swap-devices.nix
    ./system.nix
    ./systemd.nix
    ./virtualisation.nix
    ./wayland.nix
    ./xdg.nix
  ];
};
