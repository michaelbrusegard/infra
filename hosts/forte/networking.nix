{
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

    # Bambu Lab printers answer SSDP discovery on UDP 1990/2021 in LAN mode;
    # OrcaSlicer needs these inbound for the printer to show up.
    firewall.allowedUDPPorts = [1990 2021];
  };

  environment.persistence."/persistent".directories = [
    "/etc/NetworkManager/system-connections"
    "/var/lib/iwd"
  ];
}
