_: {
  # The standalone app rather than nix-darwin's tailscaled, matching how the
  # NetBird client is installed: it brings the menu bar UI and SSO login.
  homebrew.casks = ["tailscale-app"];
}
