_: {
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
}
