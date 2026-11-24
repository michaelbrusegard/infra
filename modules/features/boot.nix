{
  flake.modules.nixos.boot = {
    boot = {
      initrd.systemd.enable = true;
      tmp.cleanOnBoot = true;
    };
  };
}
