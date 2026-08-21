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
  keepTagArgs = lib.concatMapStringsSep " " (tag: "--keep-tag ${lib.escapeShellArg tag}") config.services.restic.server.maintenance.keepTags;
  pruneExcludeGroupArgs = lib.escapeShellArgs config.services.restic.server.maintenance.pruneExcludeGroups;
  freshness = config.services.restic.server.maintenance.freshness;
  freshnessEntries = lib.concatStringsSep "\n" (lib.mapAttrsToList (repo: maxAge: "${repo}:${toString maxAge}") freshness.maxAgeSeconds);
  groupEntries = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: passwordFile: "${name}:${passwordFile}") passwordFiles);
  repoEntries = lib.concatStringsSep "\n" (lib.flatten (lib.mapAttrsToList (group: repos: map (repo: "${group}:${repo}") repos) repositories));
  resticToolCommon = ''
    data_dir="${dataDir}"
    export RESTIC_CACHE_DIR="''${RESTIC_CACHE_DIR:-/tmp/restic-tools-cache-$(id -u)}"
    mkdir -p "$RESTIC_CACHE_DIR"

    die() {
      echo "$*" >&2
      exit 1
    }

    use_repo() {
      if [ "$#" -lt 1 ]; then
        die "missing repository path, expected service/repo"
      fi

      repo_arg="$1"
      case "$repo_arg" in
        /*|*..*|""|*/*/*)
          die "invalid repository path: $repo_arg"
          ;;
      esac

      service="''${repo_arg%%/*}"
      repo_name="''${repo_arg#*/}"
      if [ "$service" = "$repo_name" ]; then
        die "invalid repository path: $repo_arg"
      fi

      repo="$data_dir/$repo_arg"
      password_file="/run/secrets/restic/passwords/$service"

      [ -f "$repo/config" ] || die "restic repository not found: $repo"
      [ -r "$password_file" ] || die "cannot read $password_file; run with sudo"

      export RESTIC_PASSWORD_FILE="$password_file"
    }

    list_repos() {
      find "$data_dir" -mindepth 2 -maxdepth 3 -type f -name config -printf '%h\n' \
        | sort \
        | while IFS= read -r repo_path; do
          printf '%s\n' "''${repo_path#"$data_dir"/}"
        done
    }
  '';
  resticRepos = pkgs.writeShellApplication {
    name = "restic-repos";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.jq
      pkgs.restic
    ];
    text = ''
      set -euo pipefail
      ${resticToolCommon}

      printf '%-36s %9s %10s %s\n' repository snapshots disk latest
      printf '%-36s %9s %10s %s\n' ---------- --------- ---- ------

      while IFS= read -r repo_arg; do
        use_repo "$repo_arg"
        disk_usage=$(du -sh "$repo" | cut -f1)
        snapshots_json=$(restic -r "$repo" snapshots --json)
        snapshot_count=$(printf '%s' "$snapshots_json" | jq 'length')
        latest_snapshot=$(printf '%s' "$snapshots_json" | jq -r 'if length == 0 then "-" else max_by(.time).time end')
        printf '%-36s %9s %10s %s\n' "$repo_arg" "$snapshot_count" "$disk_usage" "$latest_snapshot"
      done < <(list_repos)
    '';
  };
  resticSnapshots = pkgs.writeShellApplication {
    name = "restic-snapshots";
    runtimeInputs = [pkgs.coreutils pkgs.restic];
    text = ''
      set -euo pipefail
      ${resticToolCommon}

      use_repo "''${1:-}"
      shift
      restic -r "$repo" snapshots --compact "$@"
    '';
  };
  resticLs = pkgs.writeShellApplication {
    name = "restic-ls";
    runtimeInputs = [pkgs.coreutils pkgs.restic];
    text = ''
      set -euo pipefail
      ${resticToolCommon}

      use_repo "''${1:-}"
      shift
      snapshot="''${1:-latest}"
      if [ "$#" -gt 0 ]; then
        shift
      fi
      restic -r "$repo" ls "$snapshot" "$@"
    '';
  };
  resticStats = pkgs.writeShellApplication {
    name = "restic-stats";
    runtimeInputs = [pkgs.coreutils pkgs.restic];
    text = ''
      set -euo pipefail
      ${resticToolCommon}

      use_repo "''${1:-}"
      echo "repository: $repo_arg"
      du -sh "$repo"
      echo
      restic -r "$repo" snapshots --compact
      echo
      restic -r "$repo" stats latest
      echo
      restic -r "$repo" stats --mode raw-data
    '';
  };
  resticCheckOne = pkgs.writeShellApplication {
    name = "restic-check-one";
    runtimeInputs = [pkgs.coreutils pkgs.restic];
    text = ''
      set -euo pipefail
      ${resticToolCommon}

      use_repo "''${1:-}"
      restic -r "$repo" check
    '';
  };
  resticRestoreTo = pkgs.writeShellApplication {
    name = "restic-restore-to";
    runtimeInputs = [pkgs.coreutils pkgs.restic];
    text = ''
      set -euo pipefail
      ${resticToolCommon}

      use_repo "''${1:-}"
      target="''${2:-}"
      snapshot="''${3:-latest}"

      [ -n "$target" ] || die "usage: restic-restore-to service/repo target-dir [snapshot]"
      mkdir -p "$target"
      restic -r "$repo" restore "$snapshot" --target "$target"
    '';
  };
  maintenance = pkgs.writeShellApplication {
    name = "restic-maintenance";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.jq
      pkgs.restic
      pkgs.util-linux
    ];
    text = ''
      set -euo pipefail

      mode="''${1:-forget}"
      case "$mode" in
        forget|prune|check|init|metrics|unlock) ;;
        *)
          echo "usage: restic-maintenance [forget|prune|check|init|metrics|unlock]" >&2
          exit 64
          ;;
      esac

      exec 9>/run/restic-maintenance/lock
      if ! flock -n 9; then
        echo "another restic maintenance job is already running"
        exit 0
      fi

      export RESTIC_CACHE_DIR=/var/cache/restic-maintenance
      mkdir -p "$RESTIC_CACHE_DIR"

      status=0
      keep_tag_args=(${keepTagArgs})
      prune_exclude_groups=(${pruneExcludeGroupArgs})
      metrics_tmp=""

      if [ "$mode" = "metrics" ]; then
        metrics_file="''${RESTIC_METRICS_FILE:?RESTIC_METRICS_FILE is required}"
        metrics_tmp=$(mktemp "''${metrics_file}.XXXXXX")
        trap 'rm -f "$metrics_tmp"' EXIT
        printf '%s\n' \
          '# HELP restic_repository_latest_snapshot_timestamp_seconds Unix timestamp of the latest snapshot.' \
          '# TYPE restic_repository_latest_snapshot_timestamp_seconds gauge' \
          '# HELP restic_repository_max_age_seconds Maximum acceptable snapshot age.' \
          '# TYPE restic_repository_max_age_seconds gauge' \
          >"$metrics_tmp"
      fi

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

        if [ "$mode" = "metrics" ]; then
          repo_arg="''${repo#"${dataDir}/"}"
          snapshots_json=""
          if ! snapshots_json=$(restic --retry-lock 15m -r "$repo" snapshots --json); then
            echo "restic metrics failed for $repo" >&2
            status=1
            return
          fi

          latest_snapshot_time=$(printf '%s' "$snapshots_json" | jq -r 'if length == 0 then empty else max_by(.time).time end')
          if [ -n "$latest_snapshot_time" ]; then
            latest_snapshot=$(date --date="$latest_snapshot_time" +%s)
          else
            latest_snapshot=0
          fi
          max_age=${toString freshness.defaultMaxAgeSeconds}
          while IFS=: read -r candidate candidate_max_age; do
            if [ "$candidate" = "$repo_arg" ]; then
              max_age="$candidate_max_age"
              break
            fi
          done <<'FRESHNESS'
      ${freshnessEntries}
      FRESHNESS

          repo_label=$(jq -Rn --arg repository "$repo_arg" '$repository')
          printf 'restic_repository_latest_snapshot_timestamp_seconds{repository=%s} %s\n' \
            "$repo_label" "$latest_snapshot" >>"$metrics_tmp"
          printf 'restic_repository_max_age_seconds{repository=%s} %s\n' \
            "$repo_label" "$max_age" >>"$metrics_tmp"
        elif [ "$mode" = "unlock" ]; then
          if ! restic -r "$repo" unlock; then
            echo "restic unlock failed for $repo" >&2
            status=1
          fi
        elif [ "$mode" = "forget" ]; then
          if ! restic --retry-lock 15m -r "$repo" forget \
            --keep-daily ${toString retention.daily} \
            --keep-weekly ${toString retention.weekly} \
            --keep-monthly ${toString retention.monthly} \
            --keep-yearly ${toString retention.yearly} \
            "''${keep_tag_args[@]}"; then
            echo "restic forget failed for $repo" >&2
            status=1
          fi
        elif [ "$mode" = "prune" ]; then
          # Bound each repository's repack work so large repositories cannot
          # exhaust memory on the Raspberry Pi backup servers.
          if ! restic --retry-lock 15m -r "$repo" prune --max-repack-size 1G; then
            echo "restic prune failed for $repo" >&2
            status=1
          fi
        else
          if ! restic --retry-lock 15m -r "$repo" check; then
            echo "restic check failed for $repo" >&2
            status=1
          fi
        fi
      }

      maintain_group() {
        local group="$1"
        local password_file="$2"
        local base="${dataDir}/$group"
        if [ "$mode" = "prune" ]; then
          for excluded_group in "''${prune_exclude_groups[@]}"; do
            if [ "$group" = "$excluded_group" ]; then
              echo "restic prune: skipping excluded group $group"
              return
            fi
          done
        fi


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
        done < <(find "$base" -mindepth 2 -type f -name config -printf '%h\0')
      }

      if [ "$mode" = "init" ] || [ "$mode" = "metrics" ]; then
        while IFS=: read -r group repo; do
          [ -n "$group" ] || continue
          [ -n "$repo" ] || continue

          password_file=""
          while IFS=: read -r candidate candidate_password_file; do
            if [ "$candidate" = "$group" ]; then
              password_file="$candidate_password_file"
              break
            fi
          done <<'GROUPS'
      ${groupEntries}
      GROUPS

          if [ -z "$password_file" ]; then
            echo "missing password file for restic group $group" >&2
            status=1
            continue
          fi

          if [ "$mode" = "init" ]; then
            mkdir -p "${dataDir}/$group/$repo"
            chmod 700 "${dataDir}/$group"
          fi
          maintain_repo "$group" "$password_file" "${dataDir}/$group/$repo"
        done <<'REPOS'
      ${repoEntries}
      REPOS

        if [ "$mode" = "metrics" ] && [ "$status" -eq 0 ]; then
          chmod 0644 "$metrics_tmp"
          mv "$metrics_tmp" "$metrics_file"
          metrics_tmp=""
        fi

        exit "$status"
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
  maintenanceService = mode: {
    # A configuration switch should not interrupt a repository operation.
    # The new unit definition will be used on its next scheduled invocation.
    restartIfChanged = false;
    unitConfig.RequiresMountsFor = [dataDir];
    serviceConfig =
      {
        Type = "oneshot";
        ExecStart = "${maintenance}/bin/restic-maintenance ${mode}";
        User = "restic";
        Group = "restic";
        RuntimeDirectory = "restic-maintenance";
        RuntimeDirectoryPreserve = true;
        CacheDirectory = "restic-maintenance";
        CacheDirectoryMode = "0700";
        Nice = 10;
        IOSchedulingClass = "idle";
      }
      // lib.optionalAttrs (builtins.elem mode ["prune" "check"]) {
        # Keep index-heavy maintenance from exhausting zram and making the
        # backup host unreachable. OOMPolicy stops the whole unit so the
        # cleanup below can release any repository locks.
        Environment = ["GOMEMLIMIT=2GiB"];
        MemoryHigh = "2G";
        MemoryMax = "3G";
        MemorySwapMax = "512M";
        OOMPolicy = "stop";
        TimeoutStartSec = "24h";
      }
      // lib.optionalAttrs (mode != "unlock") {
        # A stopped restic process can leave a repository lock behind. Run a
        # separate cleanup process after every exit, including failures.
        ExecStopPost = "${maintenance}/bin/restic-maintenance unlock";
      };
  };
in {
  options.services.restic.server = {
    initializeRepositories = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = {};
      description = "Restic REST repository directories to create and initialize locally.";
    };

    maintenance.keepTags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Restic snapshot tags to always keep during repository maintenance.";
    };
    maintenance.pruneExcludeGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Repository groups excluded from local prune maintenance.";
    };

    maintenance.freshness = {
      defaultMaxAgeSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 36 * 60 * 60;
        description = "Default maximum snapshot age exported for alerting.";
      };

      maxAgeSeconds = lib.mkOption {
        type = lib.types.attrsOf lib.types.ints.positive;
        default = {};
        description = "Per-repository maximum snapshot ages, keyed by service/repository.";
      };
    };
  };

  config = {
    # Repository pruning can briefly exceed the physical memory available on
    # the Raspberry Pi backup servers. Compressed swap prevents an interrupted
    # prune from leaving repositories locked.
    zramSwap.enable = true;

    # Restic checks can cache several gigabytes of repository indexes. Keep
    # that cache on persistent storage instead of the hosts' RAM-backed root.
    environment.persistence."/persistent".directories = [
      {
        directory = "/var/cache/restic-maintenance";
        user = "restic";
        group = "restic";
        mode = "0700";
      }
    ];

    environment.systemPackages = [
      pkgs.restic
      resticCheckOne
      resticLs
      resticRepos
      resticRestoreTo
      resticSnapshots
      resticStats
    ];

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

    services.prometheus.exporters.node = {
      enable = true;
      enabledCollectors = [
        "systemd"
        "textfile"
      ];
      extraFlags = ["--collector.textfile.directory=/var/lib/restic-metrics"];
    };

    systemd = {
      services = {
        restic-rest-server.unitConfig.RequiresMountsFor = [dataDir];

        restic-maintenance = maintenanceService "forget";
        restic-prune = maintenanceService "prune";
        restic-initialize = maintenanceService "init";
        restic-check = maintenanceService "check";
        restic-metrics = lib.recursiveUpdate (maintenanceService "metrics") {
          serviceConfig = {
            Environment = "RESTIC_METRICS_FILE=/var/lib/restic-metrics/restic.prom";
            StateDirectory = "restic-metrics";
            StateDirectoryMode = "0755";
          };
        };
        restic-unlock = maintenanceService "unlock";
      };

      timers = {
        restic-maintenance = {
          wantedBy = ["timers.target"];
          timerConfig = {
            # Apply retention daily without the expensive prune operation.
            OnCalendar = "*-*-* 12:00";
            Persistent = true;
            RandomizedDelaySec = "1h";
          };
        };

        restic-prune = {
          wantedBy = ["timers.target"];
          timerConfig = {
            # Reclaim space weekly, well outside the overnight backup window.
            OnCalendar = "Sat 14:00";
            Persistent = true;
            RandomizedDelaySec = "1h";
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

        restic-metrics = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "*-*-* *:15:00";
            Persistent = true;
          };
        };

        # Recover locks left by power loss or anything that prevents a
        # service's ExecStopPost cleanup from running. Active locks are kept.
        restic-unlock = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "*-*-* *:05:00";
            Persistent = true;
          };
        };
      };
    };
  };
}
