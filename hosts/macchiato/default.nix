{inputs, ...}: {
  imports = [

    inputs.self.nixosModules.boot
    inputs.self.nixosModules.blocky
    inputs.self.nixosModules.blocky-prometheus
    inputs.self.nixosModules.bluetooth
    inputs.self.nixosModules.catppuccin
    inputs.self.nixosModules.console
    inputs.self.nixosModules.cloudflare-dyndns
    inputs.self.nixosModules.disable-documentation
    inputs.self.nixosModules.disko
    inputs.self.nixosModules.grafana
    inputs.self.nixosModules.grafana-blocky
    inputs.self.nixosModules.homebridge
    inputs.self.nixosModules.home-manager
    inputs.self.nixosModules.lanzaboote
    inputs.self.nixosModules.locale
    inputs.self.nixosModules.networking
    inputs.self.nixosModules.nix
    inputs.self.nixosModules.openssh
    inputs.self.nixosModules.prometheus
    inputs.self.nixosModules.security
    ./disko.nix
    ./hardware.nix
    ./networking.nix
  ];

  system.stateVersion = "25.11";
}
