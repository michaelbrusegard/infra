{config, ...}: {
  networking.firewall = {
    allowedTCPPorts = [53 9090 3000 1883 8080 8581];
    allowedUDPPorts = [51820 53];
  };

  networking.nat = {
    enable = true;
    internalInterfaces = ["wg0"];
    externalInterface = "end0";
  };

  services.wireguard.interfaces.wg0 = {
    ips = ["10.0.187.1/24"];
    listenPort = 51820;
    inherit (config.secrets.wireguard) privateKeyFile;
    inherit (config.secrets.wireguard) peers;
  };

  services.avahi.allowInterfaces = ["end0" "wg0"];
}
