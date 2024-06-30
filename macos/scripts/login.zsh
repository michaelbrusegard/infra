#!/usr/bin/env zsh

set -e  # Abort the script if any command fails
set -x  # Print commands and their arguments as they are executed

# Function to add application to login items
add_login_item() {
    local app_name="$1"
    local app_path="/Applications/${app_name}.app"
    osascript <<EOF
tell application "System Events"
    if not (exists login item "$app_name") then
        make new login item at end with properties {path:"$app_path", hidden:true}
    end if
end tell
EOF
}

# Configure scripting addition to inject into the Dock
echo "$(whoami) ALL=(root) NOPASSWD: sha256:$(shasum -a 256 $(which yabai) | cut -d " " -f 1) $(which yabai) --load-sa" | sudo tee /private/etc/sudoers.d/yabai

# Start yabai automatically
yabai --start-service

# Enable launch at login for AltServer
osascript <<EOF
tell application "System Events"
    tell application "AltServer" to activate
    delay 2
    tell application "System Events" to tell process "AltServer"
        click menu item "Launch at Login" of menu "AltServer" of menu bar item "AltServer" of menu bar 1
    end tell
end tell
EOF

# Add Ice menu bar as a login item
add_login_item "Ice"

# Add Raycast as a login item
add_login_item "Raycast"

# Add Yabaiindicator as a login item
add_login_item "Yabaiindicator"

# Start colima container runtime
brew services start colima

# Rebuild bat cache to enable themes
bat cache --build

echo "Done. Applications have been set to launch at login."
