{ ... }: {
  imports = [
    ./documentation.nix
    ./environment.nix
    ./hardware.nix
    ./networking.nix
    ./services.nix
    ./users.nix
  ];
}
