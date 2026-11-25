{ inputs, ... }: {
  hosts.freddo = {
    system = "aarch64-linux";
    users = [
      "admin"
      "deploy"
    ];
    platform = "raspberrypi";
    deploy = { };
  };

  flake.modules.nixos.freddo = {
    imports = with inputs.self.modules.nixos; [
      backup-server
    ];

    time.timeZone = "Europe/Oslo";

    services.restic.server.initializeRepositories = {
      bazarr = [ "repo-config" ];
      # The LLM archive: proxy capture and its derived conversation tables.
      clickhouse = [ "pvc" ];
      cliproxy = [ "pvc" ];
      hermes-agent = [ "pvc" ];
      healthlog = [ "postgres" ];
      hindsight = [ "postgres" ];
      immich = [
        "postgres"
        "uploads"
      ];
      jellyfin = [ "repo-config" ];
      # Personal Stalwart mailbox store and Bulwark webmail settings.
      mail = [
        "bulwark-settings"
        "stalwart"
      ];
      minecraft-creative = [ "world" ];
      minecraft-revelation = [ "world" ];
      minecraft-vanilla = [ "world" ];
      media-music = [ "repo-library" ];
      mattermost = [
        "postgres"
        "pvc"
      ];
      mealie = [
        "postgres"
        "pvc"
      ];
      musicgrabber = [ "repo-config" ];
      navidrome = [ "repo-data" ];
      netbird = [ "pvc" ];
      nextcloud = [
        "postgres"
        "pvc"
      ];
      opencloud = [ "pvc" ];
      pocket-id = [ "pvc" ];
      prowlarr = [ "repo-config" ];
      radarr = [ "repo-config" ];
      seerr = [ "repo-config" ];
      sonarr = [ "repo-config" ];
      # The live smtp-edge queue still backs up under the old Stalwart group.
      stalwart = [ "smtp-edge-pvc" ];
      transmission = [ "repo-config" ];
      vaultwarden = [ "pvc" ];
    };

    services.restic.server.maintenance.keepTags = [ "legacy-minecraft" ];
    services.restic.server.maintenance.pruneExcludeGroups = [ "nextcloud" ];

    # Minecraft worlds are backed up only after player activity, so snapshot age
    # does not indicate backup health for these repositories.
    services.restic.server.maintenance.freshness.excludedRepositories = [
      "minecraft-creative/world"
      "minecraft-revelation/world"
      "minecraft-vanilla/world"
      # Nextcloud was replaced by OpenCloud; its last backups are kept as is.
      "nextcloud/postgres"
      "nextcloud/pvc"
    ];

    # Media configuration is backed up weekly; all other repositories use the
    # module's 36-hour freshness threshold.
    services.restic.server.maintenance.freshness.maxAgeSeconds = {
      "bazarr/repo-config" = 8 * 24 * 60 * 60;
      "jellyfin/repo-config" = 8 * 24 * 60 * 60;
      "navidrome/repo-data" = 8 * 24 * 60 * 60;
      "prowlarr/repo-config" = 8 * 24 * 60 * 60;
      "radarr/repo-config" = 8 * 24 * 60 * 60;
      "seerr/repo-config" = 8 * 24 * 60 * 60;
      "sonarr/repo-config" = 8 * 24 * 60 * 60;
      "transmission/repo-config" = 8 * 24 * 60 * 60;
    };

    system.stateVersion = "26.05";
  };
}
