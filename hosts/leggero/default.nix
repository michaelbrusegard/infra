{inputs, ...}: {
  imports = [
    inputs.self.nixosModules.avahi
    inputs.self.nixosModules.blocky
    inputs.self.nixosModules.blocky-prometheus
    inputs.self.nixosModules.boot
    inputs.self.nixosModules.caddy
    inputs.self.nixosModules.catppuccin
    inputs.self.nixosModules.cloudflare-dyndns
    inputs.self.nixosModules.disable-documentation
    inputs.self.nixosModules.grafana
    inputs.self.nixosModules.grafana-blocky
    inputs.self.nixosModules.home-manager
    inputs.self.nixosModules.home-assistant
    inputs.self.nixosModules.locale
    inputs.self.nixosModules.networking
    inputs.self.nixosModules.nix
    inputs.self.nixosModules.openssh
    inputs.self.nixosModules.prometheus
    inputs.self.nixosModules.security
    ./hardware.nix
    ./networking.nix
    ./openthread-border-router.nix
    ./home-assistant.nix
  ];
}
