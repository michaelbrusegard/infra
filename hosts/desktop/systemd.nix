{ ... }: {
  systemd.services.fancontrol = {
    after = [ "sensors.service" ];
    wants = [ "sensors.service" ];
  };
}
