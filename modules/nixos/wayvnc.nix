{config, ...}: {
  # Installs wayvnc plus the `wayvnc` PAM stack it authenticates against.
  programs.wayvnc.enable = true;

  # Apple Diffie-Hellman, the only security type macOS Screen Sharing offers a
  # wlroots server, leaves the session unencrypted once the handshake is done,
  # so WireGuard is what protects it: reachable over NetBird and nowhere else.
  networking.firewall.interfaces.${config.services.netbird.clients.default.interface}.allowedTCPPorts = [5900];
}
