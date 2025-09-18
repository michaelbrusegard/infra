{ ... }: {
  imports = [
    ./documentation.nix
    ./hardware.nix
    ./networking.nix
    ./services.nix
    ./users.nix
  ];
}
