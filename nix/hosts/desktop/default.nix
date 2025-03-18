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
    ./security.nix
    ./services.nix
    ./system.nix
    ./systemd.nix
    ./virtualisation.nix
    ./xdg.nix
  ];
};
