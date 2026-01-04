_: {
  boot = {
    initrd.systemd.enable = true;
    initrd.luks.devices.cryptroot = {
      crypttabExtraOpts = ["tpm2-device=auto"];
    };
    tmp.cleanOnBoot = true;
  };
}
