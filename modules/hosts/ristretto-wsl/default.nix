{inputs, ...}: {
  hosts.ristretto-wsl = {
    system = "x86_64-linux";
    users = ["michaelbrusegard"];
    platform = "wsl";
    secrets = "ristretto";
  };

  flake.modules.nixos.ristretto-wsl = {
    imports = [
      inputs.self.modules.nixos.boot
      inputs.self.modules.nixos.catppuccin
      inputs.self.modules.nixos.home-manager
      inputs.self.modules.nixos.locale
      inputs.self.modules.nixos.networking
      inputs.self.modules.nixos.nh
      inputs.self.modules.nixos.nix
      inputs.self.modules.nixos.openssh
      inputs.self.modules.nixos.security
      inputs.self.modules.nixos.ssh-agent
      inputs.self.modules.nixos.virtualisation
      inputs.self.modules.nixos.wsl
    ];

    time.timeZone = "Europe/Oslo";

    system.stateVersion = "25.11";
  };
}
