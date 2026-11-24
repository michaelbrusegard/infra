{inputs, ...}: {
  hosts.cortado = {
    system = "x86_64-linux";
    users = ["admin" "deploy"];
    deploy.buildOnTarget = true;
  };

  flake.modules.nixos.cortado = {
    imports = [
      inputs.self.modules.nixos.blocky
      inputs.self.modules.nixos.boot
      inputs.self.modules.nixos.console
      inputs.self.modules.nixos.cloudflare-dyndns
      inputs.self.modules.nixos.disable-documentation
      inputs.self.modules.nixos.disko
      inputs.self.modules.nixos.home-assistant
      inputs.self.modules.nixos.impermanence
      inputs.self.modules.nixos.lanzaboote
      inputs.self.modules.nixos.locale
      inputs.self.modules.nixos.netbird
      inputs.self.modules.nixos.netbird-relay
      inputs.self.modules.nixos.networking
      inputs.self.modules.nixos.nh
      inputs.self.modules.nixos.nix
      inputs.self.modules.nixos.openssh
      inputs.self.modules.nixos.security
      inputs.self.modules.nixos.unifi
      inputs.self.modules.nixos.watchdog
      inputs.self.modules.nixos.smtp-backup
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
  };
}
