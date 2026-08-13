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

  time.timeZone = "Europe/Oslo";

  services.restic.server.initializeRepositories = {
    bazarr = ["repo-config"];
    cliproxyapi = ["pvc"];
    hermes-agent = ["pvc"];
    healthlog = ["postgres"];
    hindsight = ["postgres"];
    immich = [
      "postgres"
      "uploads"
    ];
    jellyfin = ["repo-config"];
    minecraft-creative = ["world"];
    minecraft-revelation = ["world"];
    minecraft-vanilla = ["world"];
    media-music = ["repo-library"];
    mattermost = [
      "postgres"
      "pvc"
    ];
    mealie = [
      "postgres"
      "pvc"
    ];
    musicgrabber = ["repo-config"];
    navidrome = ["repo-data"];
    netbird = ["pvc"];
    nextcloud = [
      "postgres"
      "pvc"
    ];
    pocket-id = ["pvc"];
    prowlarr = ["repo-config"];
    radarr = ["repo-config"];
    seerr = ["repo-config"];
    sonarr = ["repo-config"];
    stalwart = ["pvc"];
    transmission = ["repo-config"];
  };

  services.restic.server.maintenance.keepTags = ["legacy-minecraft"];

  # Media configuration and Minecraft worlds are backed up weekly; all other
  # repositories use the module's 36-hour freshness threshold.
  services.restic.server.maintenance.freshness.maxAgeSeconds = {
    "bazarr/repo-config" = 8 * 24 * 60 * 60;
    "jellyfin/repo-config" = 8 * 24 * 60 * 60;
    "minecraft-creative/world" = 8 * 24 * 60 * 60;
    "minecraft-revelation/world" = 8 * 24 * 60 * 60;
    "minecraft-vanilla/world" = 8 * 24 * 60 * 60;
    "navidrome/repo-data" = 8 * 24 * 60 * 60;
    "prowlarr/repo-config" = 8 * 24 * 60 * 60;
    "radarr/repo-config" = 8 * 24 * 60 * 60;
    "seerr/repo-config" = 8 * 24 * 60 * 60;
    "sonarr/repo-config" = 8 * 24 * 60 * 60;
    "transmission/repo-config" = 8 * 24 * 60 * 60;
  };

  system.stateVersion = "26.05";
}
