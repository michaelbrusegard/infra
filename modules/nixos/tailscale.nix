{
  lib,
  users,
  ...
}: {
  # Client for joining an external tailnet alongside NetBird.
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "client";
    extraSetFlags =
      [
        # Tailscale's netfilter rules drop 100.64.0.0/10 traffic arriving on
        # any other interface, which includes NetBird's 100.102.0.0/16 peers.
        # Its userspace packet filter still applies tailnet ACLs, and the
        # NixOS firewall keeps tailscale0 closed to inbound connections.
        "--netfilter-mode=off"
      ]
      ++ lib.optional (builtins.elem "michaelbrusegard" users)
      "--operator=michaelbrusegard";
  };

  environment.persistence."/persistent".directories = [
    "/var/lib/tailscale"
  ];
}
