{ nixos-wsl, ... }: {
  imports = [
    nixos-wsl.nixosModules.default
    ./system.nix
    ./virtualisation.nix
    ./wsl.nix
  ];
}
