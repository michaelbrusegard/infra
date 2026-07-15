{config, ...}: {
  networking = {
    wireless.iwd.enable = true;
    networkmanager = {
      enable = true;
      wifi = {
        backend = "iwd";
        powersave = false;
      };
    };
    dhcpcd.enable = false;
    firewall.interfaces.${config.services.netbird.clients.default.interface}.allowedTCPPorts = [6767];
  };

  environment.persistence."/persistent".directories = [
    "/etc/NetworkManager/system-connections"
    "/var/lib/iwd"
  ];
}
