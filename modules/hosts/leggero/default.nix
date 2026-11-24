{inputs, ...}: {
  hosts.leggero = {
    system = "aarch64-linux";
    users = ["admin" "deploy"];
    platform = "raspberrypi";
    deploy = {};
  };

  flake.modules.nixos.leggero = {
    imports = with inputs.self.modules.nixos; [
      server
      blocky
      blocky-prometheus
      catppuccin
      home-assistant
      home-manager
      openthread-border-router
      prometheus
    ];

    time.timeZone = "Europe/Oslo";

    system.stateVersion = "25.11";
  };
}
