{inputs, ...}: {
  imports = [
    inputs.self.nixosModules.boot
    inputs.self.nixosModules.console
    inputs.self.nixosModules.disable-documentation
    inputs.self.nixosModules.impermanence
    inputs.self.nixosModules.locale
    inputs.self.nixosModules.networking
    inputs.self.nixosModules.nh
    inputs.self.nixosModules.nix
    inputs.self.nixosModules.openssh
    inputs.self.nixosModules.prometheus
    inputs.self.nixosModules.restic-server
    inputs.self.nixosModules.sd-grow
    inputs.self.nixosModules.security
    inputs.self.nixosModules.watchdog
    inputs.self.nixosModules.zsh-admin-rc
    ./hardware.nix
    ./networking.nix
  ];

  services.restic.server.initializeRepositories = {
    hermes-agent = ["pvc"];
    immich = [
      "postgres"
      "uploads"
    ];
    media = [
      "bazarr"
      "jellyfin"
      "jellyseerr"
      "lidarr"
      "navidrome"
      "prowlarr"
      "radarr"
      "sonarr"
      "transmission"
    ];
    minecraft = [
      "creative"
      "revelation"
      "vanilla"
    ];
    honcho = ["postgres"];
    netbird = ["pvc"];
    nextcloud = [
      "postgres"
      "pvc"
    ];
    pocket-id = ["pvc"];
    stalwart = ["pvc"];
  };

  system.stateVersion = "26.05";
}
