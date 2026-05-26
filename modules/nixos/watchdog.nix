_: {
  # Auto-reboot on kernel fault or full hang. `panic_on_oops` catches traps;
  # the rest cover the harder case: a D-state cascade (e.g. Mayastor / NVMe-TCP
  # I/O wedge) where the scheduler is fine, PID 1 keeps petting the chipset
  # watchdog, but every userspace task is blocked. Without these, the only
  # recovery is a physical hard reset.
  boot.kernel.sysctl = {
    "kernel.panic" = 10;
    "kernel.panic_on_oops" = 1;
    "kernel.hung_task_panic" = 1;
    "kernel.hung_task_timeout_secs" = 120;
    "kernel.softlockup_panic" = 1;
    "kernel.nmi_watchdog" = 1;
    "kernel.panic_on_rcu_stall" = 1;
  };

  # systemd pings /dev/watchdog0; the chipset timer resets the box if PID 1
  # (or the whole kernel) stops responding.
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "15s";
    RebootWatchdogSec = "5min";
  };
}
