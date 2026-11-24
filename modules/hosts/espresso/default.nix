{
  inputs,
  lib,
  ...
}: {
  hosts = lib.genAttrs ["espresso-0" "espresso-1" "espresso-2"] (_: {
    system = "x86_64-linux";
    users = ["admin" "deploy"];
    configuration = "espresso";
    deploy.buildOnTarget = true;
  });

  flake.modules.nixos.espresso = {
    imports = [
      inputs.self.modules.nixos.boot
      inputs.self.modules.nixos.catppuccin
      inputs.self.modules.nixos.console
      inputs.self.modules.nixos.disable-documentation
      inputs.self.modules.nixos.disko
      inputs.self.modules.nixos.impermanence
      inputs.self.modules.nixos.k3s
      inputs.self.modules.nixos.kata
      inputs.self.modules.nixos.home-manager
      inputs.self.modules.nixos.lanzaboote
      inputs.self.modules.nixos.locale
      inputs.self.modules.nixos.networking
      inputs.self.modules.nixos.nh
      inputs.self.modules.nixos.netconsole
      inputs.self.modules.nixos.nix
      inputs.self.modules.nixos.openssh
      inputs.self.modules.nixos.rasdaemon
      inputs.self.modules.nixos.security
      inputs.self.modules.nixos.smartctl-exporter
      inputs.self.modules.nixos.watchdog
    ];

    time.timeZone = "Europe/Oslo";

    system.stateVersion = "25.11";
  };
}
