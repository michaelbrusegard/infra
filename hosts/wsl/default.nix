{ nixos-wsl, ... }: {
  imports = [
    nixos-wsl.nixosModules.default
    ./virtualisation.nix
    ./wsl.nix
  ];
}
