{...}: {
  boot = {
    initrd.systemd.enable = true;
    tmp.cleanOnBoot = true;
  };
}
