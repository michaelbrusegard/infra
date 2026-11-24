{inputs, ...}: {
  hosts.ristretto = {
    system = "x86_64-linux";
    users = ["michaelbrusegard"];
  };

  flake.modules.nixos.ristretto = {
    imports = with inputs.self.modules.nixos; [
      desktop
    ];

    time.timeZone = "Europe/Oslo";

    system.stateVersion = "25.11";
  };
}
