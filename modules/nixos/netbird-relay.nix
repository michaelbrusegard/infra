{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.netbirdRelay;
in {
  options.local.netbirdRelay = {
    enable = lib.mkEnableOption "NetBird relay";

    # Relays do not federate: peers meet on whichever instance they were told
    # about, so this URL is the instance's identity and has to be unique
    # across every relay listed in the management server's Relay.Addresses.
    exposedAddress = lib.mkOption {
      type = lib.types.str;
      example = "rels://netbird.midgard.michaelbrusegard.com:443";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:33080";
    };

    # Must hold NB_AUTH_SECRET matching the management server's Relay.Secret.
    environmentFile = lib.mkOption {
      type = lib.types.path;
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.netbird-relay = {
      description = "NetBird relay";
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];
      after = ["network-online.target"];

      environment = {
        NB_LISTEN_ADDRESS = cfg.listenAddress;
        NB_EXPOSED_ADDRESS = cfg.exposedAddress;
        NB_LOG_LEVEL = "info";
        # TLS terminates in Caddy, so the peer address arrives in a header
        # that is only trustworthy coming from the local proxy.
        NB_TRUSTED_PROXIES = "127.0.0.1/32,::1/128";
      };

      serviceConfig = {
        ExecStart = lib.getExe pkgs.netbird-relay;
        EnvironmentFile = cfg.environmentFile;
        Restart = "always";
        RestartSec = 5;

        DynamicUser = true;
        CapabilityBoundingSet = [""];
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = ["AF_INET" "AF_INET6"];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = ["@system-service" "~@privileged"];
      };
    };
  };
}
