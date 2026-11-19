_: {
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
}
