{inputs, ...}: {
  hosts.ristretto-wsl = {
    system = "x86_64-linux";
    users = ["michaelbrusegard"];
    platform = "wsl";
  };

  flake.modules.nixos.ristretto-wsl = {
    imports = with inputs.self.modules.nixos; [
      workstation
      wsl
    ];

    time.timeZone = "Europe/Oslo";

    system.stateVersion = "25.11";
  };
}
