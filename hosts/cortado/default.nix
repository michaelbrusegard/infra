{inputs, ...}: {
  imports = [
    inputs.self.nixosModules.blocky
    inputs.self.nixosModules.boot
    inputs.self.nixosModules.console
    inputs.self.nixosModules.cloudflare-dyndns
    inputs.self.nixosModules.disable-documentation
    inputs.self.nixosModules.disko
    inputs.self.nixosModules.home-assistant
    inputs.self.nixosModules.impermanence
    inputs.self.nixosModules.lanzaboote
    inputs.self.nixosModules.locale
    inputs.self.nixosModules.netbird
    inputs.self.nixosModules.networking
    inputs.self.nixosModules.nh
    inputs.self.nixosModules.nix
    inputs.self.nixosModules.openssh
    inputs.self.nixosModules.security
    inputs.self.nixosModules.unifi
    inputs.self.nixosModules.watchdog
    ./disko.nix
    ./hardware.nix
    ./networking.nix
  ];

  time.timeZone = "America/Los_Angeles";

  system.stateVersion = "26.05";

  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = ["systemd"];
  };
}
