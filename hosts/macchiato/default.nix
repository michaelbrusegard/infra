{ ... }: {
  imports = [
    ./hardware.nix
    ./networking.nix
    ./services.nix
    ./system.nix
    ./users.nix
  ];
}
