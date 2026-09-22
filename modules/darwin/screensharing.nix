_: {
  # nix-darwin has no screen sharing module and macOS ships the daemon
  # disabled, so do by hand what the Sharing pane does: `enable` clears the
  # persistent disabled override, `bootstrap` loads the daemon for this boot.
  # Access control stays at the macOS default of any user who can log in, and
  # the signed-application firewall rule already lets screensharingd through.
  #
  # Linux clients reach this over NetBird with Apple Remote Desktop auth,
  # using the account's login credentials; no VNC password is set.
  system.activationScripts.postActivation.text = ''
    echo "enabling screen sharing..." >&2
    launchctl enable system/com.apple.screensharing
    if ! launchctl print system/com.apple.screensharing >/dev/null 2>&1; then
      launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist
    fi
  '';
}
