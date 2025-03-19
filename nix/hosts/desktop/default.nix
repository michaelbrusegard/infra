{ ... }: {
  imports = [
    ./console.nix
    ./environment.nix
    ./fonts.nix
    ./gtk.nix
    ./hardware.nix
    ./location.nix
    ./networking.nix
    ./programs.nix
    ./qt.nix
    ./security.nix
    ./services.nix
    ./system.nix
    ./systemd.nix
    ./virtualisation.nix
    ./wayland.nix
    ./xdg.nix
  ];
};
