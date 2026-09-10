{pkgs, ...}: let
  pstoreJournal = pkgs.writeShellApplication {
    name = "pstore-journal";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gnugrep
      systemd
    ];
    text = ''
      archive=/var/lib/systemd/pstore
      state_dir=/var/lib/systemd/pstore-journal
      seen_file="$state_dir/seen-records"

      [[ -d "$archive" ]] || exit 0

      install -d -m 0700 "$state_dir"
      touch "$seen_file"
      chmod 0600 "$seen_file"

      while IFS= read -r -d "" record; do
        relative="''${record#"$archive"/}"
        digest="$(sha256sum "$record")"
        digest="''${digest%% *}"
        record_id="$relative $digest"

        if grep -Fqx "$record_id" "$seen_file"; then
          continue
        fi

        {
          printf 'Recovered persistent kernel log from %s (sha256=%s)\n' "$record" "$digest"
          cat "$record"
        } | systemd-cat --identifier=kernel-pstore --priority=crit

        printf '%s\n' "$record_id" >>"$seen_file"
      done < <(find "$archive" -type f -name "*.txt" -print0 | sort -z)
    '';
  };
in {
  # Auto-reboot on kernel fault or full hang. Keep timeouts long enough for
  # storage-heavy recovery: Mayastor replica rebuilds, NVMe-TCP stalls, and etcd
  # catch-up can produce multi-minute pressure without being permanent. Still
  # panic on real kernel wedges so the machine recovers without physical access.
  boot.kernel.sysctl = {
    "kernel.panic" = 30;
    "kernel.panic_on_oops" = 1;
    "kernel.hung_task_panic" = 1;
    "kernel.hung_task_timeout_secs" = 600;
    "kernel.softlockup_panic" = 1;
    "kernel.watchdog_thresh" = 60;
    "kernel.nmi_watchdog" = 1;
    "kernel.panic_on_rcu_stall" = 1;
    "kernel.rcu_cpu_stall_timeout" = 120;
  };

  # systemd pings /dev/watchdog0; the chipset timer resets the box if PID 1
  # (or the whole kernel) stops responding. This catches dead PID 1, not normal
  # I/O pressure, so give it more room than the kernel lockup detectors and avoid
  # rebuild -> stall -> hard reset -> rebuild loops.
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "10min";
    RebootWatchdogSec = "10min";
    KExecWatchdogSec = "10min";
  };

  # Journald cannot flush an interrupt-context kernel panic. systemd-pstore
  # recovers the firmware-backed record on the next boot; replay each unique
  # record into the journal so normal log shipping can retain and alert on it.
  systemd.services.pstore-journal = {
    description = "Publish persistent kernel logs to the journal";
    wantedBy = ["multi-user.target"];
    wants = ["systemd-pstore.service"];
    after = ["systemd-pstore.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pstoreJournal}/bin/pstore-journal";
      UMask = "0077";
    };
  };
}
