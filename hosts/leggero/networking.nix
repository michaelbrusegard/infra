{config, ...}: {
  networking = {
    firewall = {
      allowedTCPPorts = [53 9090 3000 8123 5580 8081 8082 80 443];
      allowedUDPPorts = [51820 53];
    };
    nat = {
      enable = true;
      internalInterfaces = ["wg0"];
      externalInterface = "end0";
    };
    wireguard.interfaces.wg0 = {
      ips = ["10.0.62.1/24"];
      listenPort = 51820;
      inherit (config.secrets.wireguard) privateKeyFile;
      inherit (config.secrets.wireguard) peers;
    };
  };
  services.avahi.allowInterfaces = ["end0" "wg0"];
}
