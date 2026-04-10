{config, ...}: let
  wallpaperPath = "${config.users.users.${config.system.primaryUser}.home}/Projects/nix-config/wallpapers/twilight-peaks.png";
in {
  system.activationScripts.wallpaper.text = ''
    echo "Setting wallpaper..."
    osascript -e '
    tell application "System Events"
      set desktopCount to count of desktops
      repeat with i from 1 to desktopCount
        tell desktop i
          set picture to "${wallpaperPath}"
        end tell
      end repeat
    end tell'
    echo "Wallpaper set successfully"
  '';
}
