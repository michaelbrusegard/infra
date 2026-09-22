{config, ...}: {
  programs.wayvnc.enable = true;

  # Apple Diffie-Hellman leaves the session unencrypted after the handshake,
  # so WireGuard is what protects it: reachable over NetBird and nowhere else.
  networking.firewall.interfaces.${config.services.netbird.clients.default.interface}.allowedTCPPorts = [5900];
}
