{
  # NetBird programs per-domain rules into systemd-resolved so asgard names
  # resolve through the tunnel while everything else stays on the local
  # network. NetworkManager has to defer to it or it rewrites resolv.conf.
  services.resolved.enable = true;

  networking = {
    wireless.iwd = {
      enable = true;
      # The iwd backend ignores NetworkManager's wifi.powersave setting.
      settings.DriverQuirks.PowerSaveDisable = "mt7925e";
    };
    networkmanager = {
      enable = true;
      dns = "systemd-resolved";
      wifi = {
        backend = "iwd";
        powersave = false;
      };
    };
    dhcpcd.enable = false;
  };

  environment.persistence."/persistent".directories = [
    "/etc/NetworkManager/system-connections"
    "/var/lib/iwd"
  ];
}
