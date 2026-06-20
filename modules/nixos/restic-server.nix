{
  config,
  lib,
  pkgs,
  ...
}: let
  dataDir = "/srv/backup";
  passwordFiles = config.secrets.restic.passwordFiles;
  repositories = config.services.restic.server.initializeRepositories;
  retention = {
    daily = 14;
    weekly = 8;
    monthly = 12;
    yearly = 3;
  };
  groupEntries = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: passwordFile: "${name}:${passwordFile}") passwordFiles);
  repoEntries = lib.concatStringsSep "\n" (lib.flatten (lib.mapAttrsToList (group: repos: map (repo: "${group}:${repo}") repos) repositories));
  maintenance = pkgs.writeShellApplication {
    name = "restic-maintenance";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.restic
      pkgs.util-linux
    ];
    text = ''
      set -euo pipefail

      mode="''${1:-forget}"
      if [ "$mode" != "forget" ] && [ "$mode" != "check" ] && [ "$mode" != "init" ] && [ "$mode" != "unlock" ]; then
        echo "usage: restic-maintenance [forget|check|init|unlock]" >&2
        exit 64
      fi

      exec 9>/run/restic-maintenance/lock
      if ! flock -n 9; then
        echo "another restic maintenance job is already running"
        exit 0
      fi

      export RESTIC_CACHE_DIR=/var/cache/restic-maintenance
      mkdir -p "$RESTIC_CACHE_DIR"

      status=0

      maintain_repo() {
        local group="$1"
        local password_file="$2"
        local repo="$3"

        export RESTIC_PASSWORD_FILE="$password_file"
        echo "restic $mode: $repo"

        if [ "$mode" = "init" ]; then
          if [ -f "$repo/config" ]; then
            return
          fi

          if ! restic -r "$repo" init; then
            echo "restic init failed for $repo" >&2
            status=1
          fi
          return
        fi

        if [ "$mode" = "unlock" ]; then
          if ! restic -r "$repo" unlock; then
            echo "restic unlock failed for $repo" >&2
            status=1
          fi
        elif [ "$mode" = "forget" ]; then
          if ! restic -r "$repo" forget \
            --keep-daily ${toString retention.daily} \
            --keep-weekly ${toString retention.weekly} \
            --keep-monthly ${toString retention.monthly} \
            --keep-yearly ${toString retention.yearly} \
            --prune; then
            echo "restic forget failed for $repo" >&2
            status=1
          fi
        else
          if ! restic -r "$repo" check; then
            echo "restic check failed for $repo" >&2
            status=1
          fi
        fi
      }

      maintain_group() {
        local group="$1"
        local password_file="$2"
        local base="${dataDir}/$group"

        if [ ! -d "$base" ]; then
          echo "restic $mode: skipping missing group $group"
          return
        fi

        if [ "$mode" = "init" ]; then
          while IFS= read -r -d "" repo; do
            maintain_repo "$group" "$password_file" "$repo"
          done < <(find "$base" -mindepth 1 -maxdepth 1 -type d -print0)
          return
        fi

        if [ -f "$base/config" ]; then
          maintain_repo "$group" "$password_file" "$base"
        fi

        while IFS= read -r -d "" repo; do
          maintain_repo "$group" "$password_file" "$repo"
        done < <(find "$base" -mindepth 2 -maxdepth 2 -name config -printf '%h\0')
      }

      if [ "$mode" = "init" ]; then
        while IFS=: read -r group repo; do
          [ -n "$group" ] || continue
          [ -n "$repo" ] || continue
          mkdir -p "${dataDir}/$group/$repo"
        done <<'REPOS'
      ${repoEntries}
      REPOS
      fi

      while IFS=: read -r group password_file; do
        [ -n "$group" ] || continue
        maintain_group "$group" "$password_file"
      done <<'GROUPS'
      ${groupEntries}
      GROUPS

      exit "$status"
    '';
  };
in {
  options.services.restic.server.initializeRepositories = lib.mkOption {
    type = lib.types.attrsOf (lib.types.listOf lib.types.str);
    default = {};
    description = "Restic REST repository directories to create and initialize locally.";
  };

  config = {
    services.restic.server = {
      enable = true;
      inherit dataDir;
      appendOnly = true;
      privateRepos = true;
      listenAddress = "8000";
      prometheus = true;
      extraFlags = [
        "--htpasswd-file=${config.secrets.restic.htpasswdFile}"
      ];
    };

    systemd = {
      services = {
        restic-rest-server.unitConfig.RequiresMountsFor = [dataDir];

        restic-maintenance = {
          unitConfig.RequiresMountsFor = [dataDir];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${maintenance}/bin/restic-maintenance forget";
            User = "restic";
            Group = "restic";
            RuntimeDirectory = "restic-maintenance";
            CacheDirectory = "restic-maintenance";
            Nice = 10;
            IOSchedulingClass = "idle";
          };
        };

        restic-initialize = {
          unitConfig.RequiresMountsFor = [dataDir];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${maintenance}/bin/restic-maintenance init";
            User = "restic";
            Group = "restic";
            RuntimeDirectory = "restic-maintenance";
            CacheDirectory = "restic-maintenance";
            Nice = 10;
            IOSchedulingClass = "idle";
          };
        };

        restic-check = {
          unitConfig.RequiresMountsFor = [dataDir];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${maintenance}/bin/restic-maintenance check";
            User = "restic";
            Group = "restic";
            RuntimeDirectory = "restic-maintenance";
            CacheDirectory = "restic-maintenance";
            Nice = 10;
            IOSchedulingClass = "idle";
          };
        };

        restic-unlock = {
          unitConfig.RequiresMountsFor = [dataDir];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${maintenance}/bin/restic-maintenance unlock";
            User = "restic";
            Group = "restic";
            RuntimeDirectory = "restic-maintenance";
            CacheDirectory = "restic-maintenance";
            Nice = 10;
            IOSchedulingClass = "idle";
          };
        };
      };

      timers = {
        restic-maintenance = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
            RandomizedDelaySec = "2h";
          };
        };

        restic-check = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "Sun 08:00";
            Persistent = true;
            RandomizedDelaySec = "2h";
          };
        };
      };
    };
  };
}
