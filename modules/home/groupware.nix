{
  config,
  lib,
  pkgs,
  isWsl,
  homePersistenceRoot ? null,
  localTimeZone ? "UTC",
  ...
}: let
  enable = pkgs.stdenv.isLinux && !isWsl;

  nextcloudUrl = "https://cloud.asgard.michaelbrusegard.com/remote.php/dav";
  nextcloudUser = "michaelbrusegard";
  nextcloudPasswordCommand = [
    "${pkgs.coreutils}/bin/cat"
    config.secrets.nextcloud.davAppPasswordFile
  ];
in {
  config = lib.mkIf enable {
    home = lib.optionalAttrs (homePersistenceRoot != null) {
      persistence.${homePersistenceRoot}.directories = [
        ".local/share/calendars"
        ".local/share/contacts"
        ".local/share/khal"
        ".local/share/vdirsyncer"
      ];
    };

    programs.vdirsyncer = {
      enable = true;
      package = pkgs.vdirsyncer;
    };

    services.vdirsyncer = {
      enable = true;
      package = pkgs.vdirsyncer;
      frequency = "*:0/10";
    };

    systemd.user.services.vdirsyncer.Service.ExecStartPre = "${lib.getExe pkgs.vdirsyncer} discover";

    programs.khal = {
      enable = true;
      locale = {
        default_timezone = localTimeZone;
        local_timezone = localTimeZone;
        firstweekday = 0;
        weeknumbers = "left";
      };
    };

    programs.khard = {
      enable = true;
      settings = {
        general = {
          default_action = "list";
        };
      };
    };

    accounts.calendar = {
      basePath = ".local/share/calendars";
      accounts.nextcloud = {
        primary = true;
        remote = {
          type = "caldav";
          url = nextcloudUrl;
          userName = nextcloudUser;
          passwordCommand = nextcloudPasswordCommand;
        };
        vdirsyncer = {
          enable = true;
          collections = ["from a"];
          conflictResolution = "remote wins";
          metadata = [
            "color"
            "displayname"
          ];
        };
        khal = {
          enable = true;
          type = "discover";
        };
      };
    };

    accounts.contact = {
      basePath = ".local/share/contacts";
      accounts.nextcloud = {
        remote = {
          type = "carddav";
          url = nextcloudUrl;
          userName = nextcloudUser;
          passwordCommand = nextcloudPasswordCommand;
        };
        vdirsyncer = {
          enable = true;
          collections = ["from a"];
          conflictResolution = "remote wins";
          metadata = ["displayname"];
        };
        khard = {
          enable = true;
          type = "discover";
        };
      };
    };
  };
}
