{ ... }: {
  imports = [
    ./console.nix
    ./environment.nix
    ./gtk.nix
    ./hardware.nix
    ./location.nix
    ./networking.nix
    ./fonts.nix
    ./virtualisation.nix
  ];
};
