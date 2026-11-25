{
  flake.modules.nixos.manata = {
    networking.firewall.allowedTCPPorts = [
      8000
      9100
    ];
  };
}
