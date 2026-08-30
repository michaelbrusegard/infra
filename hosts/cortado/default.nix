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

  # Host deltas on the module's skeleton: caddy terminates TLS on this box, so
  # home assistant must trust the loopback proxy, and links it generates
  # should use the published name.
  services.home-assistant.config = {
    homeassistant.external_url = "https://home-assistant.midgard.michaelbrusegard.com";
    http = {
      use_x_forwarded_for = true;
      trusted_proxies = [
        "127.0.0.1"
        "::1"
      ];
    };
  };
}
