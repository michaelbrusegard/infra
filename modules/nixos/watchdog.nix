_: {
  # Auto-reboot on kernel fault or full hang.
  boot.kernel.sysctl = {
    "kernel.panic" = 10;
    "kernel.panic_on_oops" = 1;
  };

  # systemd pings /dev/watchdog0; the chipset timer resets the box if PID 1
  # (or the whole kernel) stops responding.
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "15s";
    RebootWatchdogSec = "5min";
  };
}
