{inputs, ...}: {
  imports = [
    inputs.self.nixosModules.alloy
    inputs.self.nixosModules.boot
    inputs.self.nixosModules.blocky
    inputs.self.nixosModules.catppuccin
    inputs.self.nixosModules.console
    inputs.self.nixosModules.cloudflare-dyndns
    inputs.self.nixosModules.disable-documentation
    inputs.self.nixosModules.disko
    inputs.self.nixosModules.homebridge
    inputs.self.nixosModules.home-manager
    inputs.self.nixosModules.impermanence
    inputs.self.nixosModules.lanzaboote
    inputs.self.nixosModules.locale
    inputs.self.nixosModules.networking
    inputs.self.nixosModules.nix
    inputs.self.nixosModules.openssh
    inputs.self.nixosModules.security
    inputs.self.nixosModules.unifi
    ./disko.nix
    ./hardware.nix
    ./networking.nix
  ];

  system.stateVersion = "25.11";

  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = ["systemd"];
  };

  environment.etc."alloy/config.alloy".text = ''
    loki.source.journal "macchiato" {
      forward_to = [loki.process.journal.receiver]
      labels = {
        host = "macchiato",
        job  = "systemd-journal",
      }
    }

    loki.process "journal" {
      forward_to = [loki.write.default.receiver]
    }

    loki.write "default" {
      endpoint {
        url = "http://10.0.188.4:3100/loki/api/v1/push"
      }
    }
  '';
}
