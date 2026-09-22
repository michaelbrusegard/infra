{config, ...}: {
  # Direct IP access is what keeps sessions off the public rendezvous
  # servers. RustDesk listens on RENDEZVOUS_PORT + 2 for it, and the mesh is
  # the only place it should be reachable from.
  networking.firewall.interfaces.${config.services.netbird.clients.default.interface}.allowedTCPPorts = [21118];
}
