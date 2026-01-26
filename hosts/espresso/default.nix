{inputs, ...}: {
  imports = [
    inputs.self.nixosModules.boot
    inputs.self.nixosModules.catppuccin
    inputs.self.nixosModules.console
    inputs.self.nixosModules.disable-documentation
    inputs.self.nixosModules.disko
    inputs.self.nixosModules.k3s
    inputs.self.nixosModules.home-manager
    inputs.self.nixosModules.lanzaboote
    inputs.self.nixosModules.locale
    inputs.self.nixosModules.networking
    inputs.self.nixosModules.nix
    inputs.self.nixosModules.openiscsi
    inputs.self.nixosModules.openssh
    inputs.self.nixosModules.security
    ./cluster.nix
    ./networking.nix
    ./hardware.nix
    ./disko.nix
  ];

  system.stateVersion = "25.11";
}
