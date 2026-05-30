{
  config,
  inputs,
  ...
}: let
  wallpaper = inputs.self + "/wallpapers/twilight-peaks.png";
  inherit (config.system) primaryUser;
in {
  # macOS keeps the desktop picture as per-user GUI state, so set it as the
  # primary user from inside their Aqua session. Re-asserted on every
  # `nh darwin switch` so the wallpaper stays declarative.
  system.activationScripts.postActivation.text = ''
    echo "setting desktop wallpaper..." >&2
    wallpaperUid=$(/usr/bin/id -u ${primaryUser})
    launchctl asuser "$wallpaperUid" sudo -u ${primaryUser} \
      /usr/bin/osascript -e 'tell application "System Events" to set picture of every desktop to "${wallpaper}"' || true
  '';
}
