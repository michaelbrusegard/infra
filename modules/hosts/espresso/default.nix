{
  inputs,
  lib,
  ...
}:
{
  hosts = lib.genAttrs [ "espresso-0" "espresso-1" "espresso-2" ] (_: {
    system = "x86_64-linux";
    users = [
      "admin"
      "deploy"
    ];
    configuration = "espresso";
    deploy.buildOnTarget = true;
  });

  flake.modules.nixos.espresso = {
    imports = with inputs.self.modules.nixos; [
      server
      catppuccin
      disko
      home-manager
      k3s
      kata
      lanzaboote
      netconsole
      rasdaemon
      smartctl-exporter
    ];

    time.timeZone = "Europe/Oslo";

    system.stateVersion = "25.11";
  };
}
