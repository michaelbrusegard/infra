{ inputs, ... }: {
  hosts.forte = {
    system = "x86_64-linux";
    users = [ "michaelbrusegard" ];
  };

  flake.modules.nixos.forte = {
    imports = with inputs.self.modules.nixos; [
      desktop
      dialpad
    ];

    time.timeZone = "America/Los_Angeles";

    system.stateVersion = "26.05";
  };
}
