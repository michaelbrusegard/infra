{ ... }: {
  imports = [
    ./boot.nix
    ./hardware.nix
    ./networking.nix
    ./services.nix
    ./system.nix
  ];
}
