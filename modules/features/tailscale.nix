{
  flake.modules.nixos.tailscale = {
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
          # any other interface, which includes NetBird's peers.
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
  };

  flake.modules.darwin.tailscale = {
    # The standalone app rather than nix-darwin's tailscaled, matching how the
    # NetBird client is installed: it brings the menu bar UI and SSO login.
    homebrew.casks = ["tailscale-app"];

    # Start at login declaratively instead of relying on the app's own toggle.
    launchd.user.agents.tailscale.serviceConfig = {
      ProgramArguments = [
        "/usr/bin/open"
        "-a"
        "Tailscale"
      ];
      RunAtLoad = true;
      LimitLoadToSessionType = "Aqua";
    };
  };
}
