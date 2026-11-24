{inputs, ...}: {
  hosts.leggero = {
    system = "aarch64-linux";
    users = ["admin" "deploy"];
    platform = "raspberrypi";
    deploy = {};
  };

  flake.modules.nixos.leggero = {
    imports = [
      inputs.self.modules.nixos.blocky
      inputs.self.modules.nixos.blocky-prometheus
      inputs.self.modules.nixos.boot
      inputs.self.modules.nixos.catppuccin
      inputs.self.modules.nixos.console
      inputs.self.modules.nixos.disable-documentation
      inputs.self.modules.nixos.home-manager
      inputs.self.modules.nixos.home-assistant
      inputs.self.modules.nixos.impermanence
      inputs.self.modules.nixos.locale
      inputs.self.modules.nixos.networking
      inputs.self.modules.nixos.nh
      inputs.self.modules.nixos.nix
      inputs.self.modules.nixos.openssh
      inputs.self.modules.nixos.openthread-border-router
      inputs.self.modules.nixos.prometheus
      inputs.self.modules.nixos.security
      inputs.self.modules.nixos.watchdog
    ];

    time.timeZone = "Europe/Oslo";

    system.stateVersion = "25.11";
  };
}
