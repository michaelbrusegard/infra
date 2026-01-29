{inputs, ...}: {
  imports = [
    inputs.self.nixosModules.boot
    inputs.self.nixosModules.catppuccin
    inputs.self.nixosModules.home-manager
    inputs.self.nixosModules.locale
    inputs.self.nixosModules.networking
    inputs.self.nixosModules.nix
    inputs.self.nixosModules.openssh
    inputs.self.nixosModules.security
    inputs.self.nixosModules.ssh-agent
    inputs.self.nixosModules.virtualisation
    inputs.self.nixosModules.wsl
  ];

  system.stateVersion = "25.11";
}
