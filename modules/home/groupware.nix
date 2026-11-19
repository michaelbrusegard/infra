{
  config,
  lib,
  pkgs,
  isWsl,
  homePersistenceRoot ? null,
  localTimeZone ? "UTC",
  ...
}: let
  enable = pkgs.stdenv.hostPlatform.isLinux && !isWsl;

  # vdirsyncer finds the CalDAV and CardDAV homes through .well-known.
  davUrl = "https://mail.asgard.michaelbrusegard.com/";
  davUser = "michaelbrusegard@michaelbrusegard.com";
  davPasswordCommand = [
    "${pkgs.coreutils}/bin/cat"
    config.secrets.mail.davAppPasswordFile
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
      accounts.asgard = {
        primary = true;
        remote = {
          type = "caldav";
          url = davUrl;
          userName = davUser;
          passwordCommand = davPasswordCommand;
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
      accounts.asgard = {
        remote = {
          type = "carddav";
          url = davUrl;
          userName = davUser;
          passwordCommand = davPasswordCommand;
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
