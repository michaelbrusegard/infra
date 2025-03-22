{ ... }: {
  imports = [
    ./boot.nix
    ./console.nix
    ./environment.nix
    ./file-systems.nix
    ./fonts.nix
    ./hardware.nix
    ./location.nix
    ./networking.nix
    ./programs.nix
    ./security.nix
    ./services.nix
    ./swap-devices.nix
    ./system.nix
    ./systemd.nix
    ./virtualisation.nix
    ./xdg.nix
  ];
}
