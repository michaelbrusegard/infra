{
  flake.modules.nixos.freddo = {
    networking.firewall.allowedTCPPorts = [
      8000
      9100
    ];
  };
}
