#!/usr/bin/env zsh

set -e  # Abort the script if any command fails
set -x  # Print commands and their arguments as they are executed

# Close System Settings panes to prevent it from overriding settings we're about to change
osascript -e 'tell application "System Settings" to quit'

# Ask for the administrator password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until script has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# ********************************************************************************
# * iCloud                                                                       *
# ********************************************************************************

# Enable Private Relay
defaults write com.apple.Safari WBSPrivacyProxyAvailabilityServiceStatus -bool true
defaults write com.apple.Safari WBSPrivacyProxyAvailabilitySubscriberTier -bool true

# Enable iCloud Drive -> Desktop & Documents Folders
defaults write com.apple.finder FXICloudDriveDesktop -bool true
defaults write com.apple.finder FXICloudDriveDocuments -bool true
defaults write com.apple.finder SidebarShowingiCloudDesktop -bool true

# ********************************************************************************
# * Bluetooth                                                                    *
# ********************************************************************************

# Increase sound quality for Bluetooth headphones/headsets
defaults write com.apple.BluetoothAudioAgent "Apple Bitpool Max (editable)" -int 80
defaults write com.apple.BluetoothAudioAgent "Apple Bitpool Min (editable)" -int 80
defaults write com.apple.BluetoothAudioAgent "Apple Initial Bitpool (editable)" -int 80
defaults write com.apple.BluetoothAudioAgent "Apple Initial Bitpool Min (editable)" -int 80
defaults write com.apple.BluetoothAudioAgent "Negotiated Bitpool" -int 80
defaults write com.apple.BluetoothAudioAgent "Negotiated Bitpool Max" -int 80
defaults write com.apple.BluetoothAudioAgent "Negotiated Bitpool Min" -int 80

# ********************************************************************************
# * Network                                                                      *
# ********************************************************************************

# Enable Firewall
sudo defaults write /Library/Preferences/com.apple.alf globalstate -bool true

# ********************************************************************************
# * Sound                                                                        *
# ********************************************************************************

# Disable the sound effects on boot
sudo nvram SystemAudioVolume=%80

# ********************************************************************************
# * General                                                                      *
# ********************************************************************************

# Empty Trash automatically after 30 days
defaults write com.apple.finder FXRemoveOldTrashItems -bool true

# Optimise Storage
defaults write com.apple.TV automaticallyDeleteVideoAssetsAfterWatching -bool true

# Preferred Languages (English-UK)
defaults write NSGlobalDomain AppleLanguages -array "en-UK" "nb-NO"

# Region (Norway)
defaults write NSGlobalDomain AppleLocale -string "en_NO@currency=nok"

# Temperature (Metric)
defaults write NSGlobalDomain AppleTemperatureUnit -string "Celsius"

# Measurement system (Metric)
defaults write NSGlobalDomain AppleMeasurementUnits -string "Centimeters"
defaults write NSGlobalDomain AppleMetricUnits -bool true

# 24-hour time
defaults write NSGlobalDomain AppleICUForce24HourTime -bool true

# Prevent Time Machine from prompting to use new hard drives as backup volume
defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true

# ********************************************************************************
# * Appearance                                                                   *
# ********************************************************************************

# Appearance (Dark)
defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark"
defaults write NSGlobalDomain AppleInterfaceStyleSwitchesAutomatically -bool false

# Accent Colour (Purple)
defaults write NSGlobalDomain AppleAccentColor -int 5
defaults write NSGlobalDomain AppleHighlightColor -string "0.968627 0.831373 1.000000 Purple"

# Sidebar icon size (Medium)
defaults write NSGlobalDomain NSTableViewDefaultSizeMode -int 2

# Set wallpaper
osascript -e 'tell application "System Events" to tell every desktop to set picture to POSIX file "'"$(find "$(dirname "$PWD")/resources" \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) | head -n 1)"'"'

# ********************************************************************************
# * Accessibility                                                                *
# ********************************************************************************

# Use scroll gesture with the Control modifier key to zoom
defaults write com.apple.universalaccess closeViewScrollWheelToggle -bool true
defaults write com.apple.universalaccess HIDScrollZoomModifierMask -int 262144

# Disable shake mouse pointer to locate
defaults write NSGlobalDomain CGDisableCursorLocationMagnification -bool true

# Disable the over-the-top focus ring animation
defaults write NSGlobalDomain NSUseAnimatedFocusRing -bool false

# ********************************************************************************
# * Control Centre                                                               *
# ********************************************************************************

# Don't show Focus in Menu Bar
defaults -currentHost write com.apple.controlcenter FocusModes -int 8

# Don't show Screen Mirroring in Menu Bar
defaults write com.apple.airplay showInMenuBarIfPresent -bool false
defaults -currentHost write com.apple.controlcenter ScreenMirroring -int 8

# Don't show Display in Menu Bar
defaults -currentHost write com.apple.controlcenter Display -int 8

# Always show Sound in Menu Bar
defaults write com.apple.controlcenter "NSStatusItem Visible Sound" -bool true
defaults -currentHost write com.apple.controlcenter Sound -int 18

# Don't show Now Playing in Menu Bar
defaults -currentHost write com.apple.controlcenter NowPlaying -int 8

# Show battery with percentage in Menu Bar
defaults write com.apple.controlcenter "NSStatusItem Visible Battery" -bool true
defaults -currentHost write com.apple.controlcenter Battery -int 6
defaults -currentHost write com.apple.controlcenter BatteryShowPercentage -bool true

# Always show date in Menu Bar
defaults write com.apple.menuextra.clock showDate -bool true

# Don't show day of the week
defaults write com.apple.menuextra.clock ShowDayOfWeek -bool false

# Don't show Siri in Menu Bar
defaults write com.apple.Siri StatusMenuVisible -bool false
defaults -currentHost write com.apple.controlcenter Siri -int 8

# Don't show Spotlight in Menu Bar
defaults -currentHost write com.apple.Spotlight MenuItemHidden -bool true

# Automatically hide and show the menu bar (In Full Screen Only)
defaults write NSGlobalDomain AppleMenuBarVisibleInFullscreen -bool false
defaults write NSGlobalDomain _HIHideMenuBar -bool false

# ********************************************************************************
# * Siri & Spotlight                                                             *
# ********************************************************************************

# Disable Siri
defaults write com.apple.assistant.support "Assistant Enabled" -bool false

# Disable spotlight
sudo mdutil -a -i off

# ********************************************************************************
# * Dock & Desktop                                                               *
# ********************************************************************************

# Size (56 pixels)
defaults write com.apple.dock tilesize -int 56

# Position on screen (Left)
defaults write com.apple.dock orientation -string "left"

# Minimise windows using (Scale Effect)
defaults write com.apple.dock mineffect -string "scale"

# Minimise windows into application icon
defaults write com.apple.dock minimize-to-application -bool true

# Automatically hide and show the Dock
defaults write com.apple.dock autohide -bool true

# Set the auto-hiding Dock delay very high to disable the dock
defaults write com.apple.dock autohide-delay -float 1000000

# Remove the animation when hiding/showing the Dock
defaults write com.apple.dock autohide-time-modifier -float 0

# Don't animate opening applications
defaults write com.apple.dock launchanim -bool false

# Show indicators for open applications
defaults write com.apple.dock show-process-indicators -bool true

# Don't show suggested and recent applications in Dock
defaults write com.apple.dock show-recents -bool false

# Enable spring loading for all Dock items
defaults write com.apple.dock enable-spring-load-actions-on-all-items -bool true

# Enable highlight hover effect for the grid view of a stack in the Dock
defaults write com.apple.dock mouse-over-hilite-stack -bool true

# Make Dock icons of hidden applications translucent
defaults write com.apple.dock showhidden -bool true

# Don't bounce apps in dock when recieving a notification
defaults write com.apple.dock no-bouncing -bool true

# Wipe all (default) app icons from the Dock
defaults write com.apple.dock persistent-apps -array

# Add a small spacer to the dock
#defaults write com.apple.dock persistent-apps -array-add '{tile-data={}; tile-type="small-spacer-tile";}'

# Lock the Dock position
defaults write com.apple.Dock position-immutable -bool true

# Lock the Dock size
defaults write com.apple.Dock size-immutable -bool true

# Lock the Dock contents
defaults write com.apple.Dock contents-immutable -bool true

# Show only open applications in the Dock
defaults write com.apple.dock static-only -bool true

# Show Items on desktop
defaults write com.apple.WindowManager HideDesktop -bool true

# Monochrome widgets
defaults write com.apple.widgets widgetAppearance -int 0

# Disable click wallpaper to reveal desktop
defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false

# Don't automatically rearrange Spaces based on most recent use
defaults write com.apple.dock mru-spaces -bool false

# Group windows by application in Mission Control
defaults write com.apple.dock expose-group-by-app -bool true

# Speed up Mission Control animations
defaults write com.apple.dock expose-animation-duration -float 0.1

# Disable Hot Corners
defaults write com.apple.dock wvous-tr-corner -int 0
defaults write com.apple.dock wvous-tr-modifier -int 0
defaults write com.apple.dock wvous-tl-corner -int 0
defaults write com.apple.dock wvous-tl-modifier -int 0
defaults write com.apple.dock wvous-tr-corner -int 0
defaults write com.apple.dock wvous-tr-modifier -int 0
defaults write com.apple.dock wvous-bl-corner -int 0
defaults write com.apple.dock wvous-bl-modifier -int 0

# ********************************************************************************
# * Displays                                                                     *
# ********************************************************************************

# Show resolutions as a list
defaults write com.apple.Displays-Settings.extension showListByDefault -bool true

# Enable subpixel font rendering on non-Apple LCDs
defaults write NSGlobalDomain AppleFontSmoothing -bool true

# Enable HiDPI display modes
defaults -currentHost write com.apple.windowserver DisplayResolutionEnabled -bool true

# ********************************************************************************
# * Lock Screen                                                                  *
# ********************************************************************************

# Require password immediately after sleep or screen saver begins
osascript -e 'tell application "System Events" to set require password to wake of security preferences to true'

# Start screensaver when inactive (For 5 minutes)
defaults -currentHost write com.apple.screensaver idleTime -int 300

# Turn display off when inactive (For 20 minutes)
sudo pmset -a displaysleep 20

# Go to sleep on battery when display has been off (For 5  minutes)
sudo pmset -b sleep 5

# Disable sleep while charging
sudo pmset -c sleep 0

# Enter standy when been asleep (For 24 hours)
sudo pmset -a standbydelay 86400

# Disable hibernation (speeds up entering sleep mode)
sudo pmset -a hibernatemode 0

# Turn display on when opening lid
sudo pmset -a lidwake 1

# Restart automatically on power loss
sudo pmset -a autorestart 1

# Restart automatically if the computer freezes
sudo systemsetup -setrestartfreeze on

# Show large clock On Screen Saver and Lock Screen
defaults -currentHost write com.apple.screensaver showClock -bool true

# ********************************************************************************
# * Keyboard                                                                     *
# ********************************************************************************

# Keyboard repeat rate
defaults write NSGlobalDomain KeyRepeat -int 1
defaults write NSGlobalDomain InitialKeyRepeat -int 10

# Press globe key to do nothing
defaults write com.apple.HIToolbox AppleFnUsageType -int 0

# Enable keyboard navigation for all controls
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

# Follow the keyboard focus while zoomed in
defaults write com.apple.universalaccess closeViewZoomFollowsFocus -bool true

# Disable press-and-hold for keys in favor of key repeat
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# Disable Turn Dock hiding on/off keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 52 "<dict><key>enabled</key><false/></dict>"

# Disable Show Launchpad keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 160 "<dict><key>enabled</key><false/></dict>"

# Disable Mission Control keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 32 "<dict><key>enabled</key><false/></dict>"

# Disable Show Notification Centre keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 163 "<dict><key>enabled</key><false/></dict>"

# Disable Turn Do Not Disturb on/off keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 175 "<dict><key>enabled</key><false/></dict>"

# Disable Show Desktop keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 36 "<dict><key>enabled</key><false/></dict>"

# Disable Application windows keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 33 "<dict><key>enabled</key><false/></dict>"

# Disable Turn Stage Manager on/off keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 222 "<dict><key>enabled</key><false/></dict>"

# Disable Move left a space keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 79 "<dict><key>enabled</key><false/></dict>"

# Disable Move right a space keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 81 "<dict><key>enabled</key><false/></dict>"

# Disable Switch to Desktop 1 keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 118 "<dict><key>enabled</key><false/></dict>"

# Disable Quick Note keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 190 "<dict><key>enabled</key><false/></dict>"

# Disable Change the way Tab moves focues keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 13 "<dict><key>enabled</key><false/></dict>"

# Disable Turn keyboard access on or off keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 12 "<dict><key>enabled</key><false/></dict>"

# Disable Move focus to the menu bar keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 7 "<dict><key>enabled</key><false/></dict>"

# Disable Move focus to the Dock keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 8 "<dict><key>enabled</key><false/></dict>"

# Disable Move focus to active or next window keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 9 "<dict><key>enabled</key><false/></dict>"

# Disable Move focus to the window toolbar keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 10 "<dict><key>enabled</key><false/></dict>"

# Disable Move focus to the floating window keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 11 "<dict><key>enabled</key><false/></dict>"

# Disable Move focus to next window keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 27 "<dict><key>enabled</key><false/></dict>"

# Disable Move focus to status menus keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 57 "<dict><key>enabled</key><false/></dict>"

# Disable Select the previous input source keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 60 "<dict><key>enabled</key><false/></dict>"

# Disable Select next source in Input menu keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 61 "<dict><key>enabled</key><false/></dict>"

# Disable Turn Presenter Overlay (small) on or off keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 224 "<dict><key>enabled</key><false/></dict>"

# Disable Turn Presenter Overlay (large) on or off keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 223 "<dict><key>enabled</key><false/></dict>"

# Disable Show Spotlight search keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 "<dict><key>enabled</key><false/></dict>"

# Disable Show Finder search window keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 65 "<dict><key>enabled</key><false/></dict>"

# Disable Contrast keyboard shortcuts
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 25 "<dict><key>enabled</key><false/></dict>"
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 26 "<dict><key>enabled</key><false/></dict>"

# Disable Invert colours keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 21 "<dict><key>enabled</key><false/></dict>"

# Disable Live Speech keyboard shortcuts
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 225 "<dict><key>enabled</key><false/></dict>"
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 226 "<dict><key>enabled</key><false/></dict>"
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 227 "<dict><key>enabled</key><false/></dict>"
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 228 "<dict><key>enabled</key><false/></dict>"
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 229 "<dict><key>enabled</key><false/></dict>"

# Disable Show Accessibility controls keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 162 "<dict><key>enabled</key><false/></dict>"

# Disable Turn speak item under the pointer on or off keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 231 "<dict><key>enabled</key><false/></dict>"

# Disable Turn speak selection on or off keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 230 "<dict><key>enabled</key><false/></dict>"

# Disable Turn typing feedback on or off keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 232 "<dict><key>enabled</key><false/></dict>"

# Disable Turn VoiceOver on or off keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 59 "<dict><key>enabled</key><false/></dict>"

# Disable Zoom keyboard shortcuts
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 15 "<dict><key>enabled</key><false/></dict>"
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 17 "<dict><key>enabled</key><false/></dict>"
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 179 "<dict><key>enabled</key><false/></dict>"
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 19 "<dict><key>enabled</key><false/></dict>"
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 23 "<dict><key>enabled</key><false/></dict>"
defaults write com.apple.universalaccess closeViewHotkeysEnabled -bool false

# Disable Show Help menu keyboard shortcut
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 98 "<dict><key>enabled</key><false/></dict>"

# Don't show Input menu in menu bar
defaults write com.apple.TextInputMenu visible -bool false

# Don't correct spelling automatically
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
defaults write NSGlobalDomain WebAutomaticSpellingCorrectionEnabled -bool false

# Don't capitalise words automatically
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false

# Don't show inline predictive text
defaults write NSGlobalDomain NSAutomaticInlinePredictionEnabled -bool false

# Don't add full stop with double-space
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false

# Don't use smart quotes and dashes
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false

# Disable dictation
defaults write com.apple.assistant.support "Dictation Enabled" -bool false

# ********************************************************************************
# * Trackpad                                                                     *
# ********************************************************************************

# Enable Silent clicking
defaults write com.apple.AppleMultitouchTrackpad ActuationStrength -bool false

# Disable Force Click and haptic feedback + Look up & data detectors
defaults write NSGlobalDomain com.apple.trackpad.forceClick -bool false
defaults write com.apple.AppleMultitouchTrackpad ActuateDetents -bool false
defaults write com.apple.AppleMultitouchTrackpad ForceSuppressed -bool true

# Set secondary click to Click or tap with Two Fingers
defaults -currentHost write NSGlobalDomain com.apple.trackpad.enableSecondaryClick -bool true
defaults write NSGlobalDomain ContextMenuGesture -bool true
defaults write com.apple.AppleMultitouchTrackpad TrackpadRightClick -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick -bool true

# Enable tap to click for this user and for the login screen
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -bool true
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true

# Disable Swipe between pages gesture
defaults write NSGlobalDomain AppleEnableSwipeNavigateWithScrolls -bool false

# Disable Swipe between full-screen applications gesture
defaults -currentHost write NSGlobalDomain com.apple.trackpad.fourFingerHorizSwipeGesture -int 0
defaults -currentHost write NSGlobalDomain com.apple.trackpad.threeFingerHorizSwipeGesture -int 0
defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerHorizSwipeGesture -int 0
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerHorizSwipeGesture -int 0
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerHorizSwipeGesture -int 0
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerHorizSwipeGesture -int 0

# Disable notification center gesture
defaults -currentHost write NSGlobalDomain com.apple.trackpad.twoFingerFromRightEdgeSwipeGesture -int 0
defaults write com.apple.AppleMultitouchTrackpad TrackpadTwoFingerFromRightEdgeSwipeGesture -int 0
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadTwoFingerFromRightEdgeSwipeGesture -int 0

# Disable mission control gesture
defaults write com.apple.dock showMissionControlGestureEnabled -bool false

# Disable App Exposé gesture
defaults -currentHost write NSGlobalDomain com.apple.trackpad.fourFingerVertSwipeGesture -int 0
defaults -currentHost write NSGlobalDomain com.apple.trackpad.threeFingerVertSwipeGesture -int 0
defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerVertSwipeGesture -int 0
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerVertSwipeGesture -int 0
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerVertSwipeGesture -int 0
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerVertSwipeGesture -int 0
defaults write com.apple.dock showAppExposeGestureEnabled -bool false

# Disable Launchpad gesture
defaults write com.apple.dock showLaunchpadGestureEnabled -bool false

# Disable Show Desktop gesture
defaults -currentHost write NSGlobalDomain com.apple.trackpad.fiveFingerPinchSwipeGesture -int 0
defaults -currentHost write NSGlobalDomain com.apple.trackpad.fourFingerPinchSwipeGesture -int 0
defaults write com.apple.AppleMultitouchTrackpad TrackpadFiveFingerPinchGesture -int 0
defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerPinchGesture -int 0
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFiveFingerPinchGesture -int 0
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerPinchGesture -int 0
defaults write com.apple.dock showDesktopGestureEnabled -bool false

# Enable window drag gesture
defaults write NSGlobalDomain NSWindowShouldDragOnGesture -bool true

# ********************************************************************************
# * Printers & Scanners                                                          *
# ********************************************************************************

# Automatically quit printer app once the print jobs complete
defaults write com.apple.print.PrintingPrefs "Quit When Finished" -bool true

# Expand print panel by default
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

# ********************************************************************************
# * Finder                                                                       *
# ********************************************************************************

# Show Hard disks, External disks, Removable Media and Connected servers on the desktop
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowMountedServersOnDesktop -bool true
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true

# Set Desktop as the default location for new Finder windows
defaults write com.apple.finder NewWindowTarget -string "PfDe"
defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/Desktop/"

# Open folders in new windows
defaults write com.apple.finder FinderSpawnTab -bool false

# Don't show recent tags in the sidebar
defaults write com.apple.finder ShowRecentTags -bool false

# Show all filename extensions
defaults write com.apple.finder AppleShowAllExtensions -bool true

# Disable warning before changing an extension
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Disable warning before removing from iCloud Drive
defaults write com.apple.finder FXEnableRemoveFromICloudDriveWarning -bool false

# Disable warning before emptying the Trash
defaults write com.apple.finder WarnOnEmptyTrash -bool false

# Remove items from the Trash after 30 days
defaults write com.apple.finder FXRemoveOldTrashItems -bool true

# Keep folders on top in windows and on desktop
defaults write com.apple.finder _FXSortFoldersFirst -bool true
defaults write com.apple.finder _FXSortFoldersFirstOnDesktop -bool true

# When performing a search, search the current folder
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

# Show hidden files by default
defaults write com.apple.finder AppleShowAllFiles -bool true

# Show status bar
defaults write com.apple.finder ShowStatusBar -bool true

# Show path bar
defaults write com.apple.finder ShowPathbar -bool true

# Display full POSIX path as Finder window title
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true

# Disable window animations and Get Info animations
defaults write com.apple.finder DisableAllAnimations -bool true

# Enable spring loading for directories
defaults write NSGlobalDomain com.apple.springing.enabled -bool true

# Remove the spring loading delay for directories
defaults write NSGlobalDomain com.apple.springing.delay -float 0

# Use list view in all Finder windows by default
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

# Set desktop view options
/usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:arrangeBy kind" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:gridSpacing 100" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:iconSize 80" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:showItemInfo true" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:showIconPreview true" ~/Library/Preferences/com.apple.finder.plist

# Set finder view options
/usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:gridSpacing 60" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:gridSpacing 60" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:iconSize 64" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:iconSize 64" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:showItemInfo true" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:showItemInfo true" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:showIconPreview true" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:showIconPreview true" ~/Library/Preferences/com.apple.finder.plist

# Expand save panel by default
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true

# Expand the following File Info panes "General", "Open with", and "Sharing & Permissions"
defaults write com.apple.finder FXInfoPanesExpanded -dict \
	General -bool true \
	OpenWith -bool true \
	Privileges -bool true

# Remove duplicates in the "Open With" menu
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user

# Automatically open a new Finder window when a volume is mounted
defaults write com.apple.frameworks.diskimages auto-open-ro-root -bool true
defaults write com.apple.frameworks.diskimages auto-open-rw-root -bool true
defaults write com.apple.finder OpenWindowForNewRemovableDisk -bool true

# ********************************************************************************
# * Quality of life                                                              *
# ********************************************************************************

# Adjust toolbar title name hover delay
defaults write NSGlobalDomain NSToolbarTitleViewRolloverDelay -float 0

# Increase window resize speed for Cocoa applications
defaults write NSGlobalDomain NSWindowResizeTime -float 0.001

# Disable the “Are you sure you want to open this application?” dialog
defaults write com.apple.LaunchServices LSQuarantine -bool false

# Display ASCII control characters using caret notation in standard text views
defaults write NSGlobalDomain NSTextShowsControlCharacters -bool true

# Disable reopening of applications with states when relaunching after quitting
defaults write com.apple.systempreferences NSQuitAlwaysKeepsWindows -bool false

# Disable automatic termination of inactive apps
defaults write NSGlobalDomain NSDisableAutomaticTermination -bool true

# Disable the crash reporter
defaults write com.apple.CrashReporter DialogType -string "none"

# Set Help Viewer windows to non-floating mode
defaults write com.apple.helpviewer DevMode -bool true

# Disable annoying disk warning
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.DiskArbitration.diskarbitrationd.plist DADisableEjectNotification -bool true

# Avoid creating .DS_Store files on network or USB volumes
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# Disable disk image verification
defaults write com.apple.frameworks.diskimages skip-verify -bool true
defaults write com.apple.frameworks.diskimages skip-verify-locked -bool true
defaults write com.apple.frameworks.diskimages skip-verify-remote -bool true

# Enable AirDrop over Ethernet
defaults write com.apple.NetworkBrowser BrowseAllInterfaces -bool true

# Show the ~/Library folder
chflags nohidden ~/Library

# Show the /Volumes folder
sudo chflags nohidden /Volumes

# Move archive files to trash after expansion
defaults write com.apple.archiveutility dearchive-move-after -string "~/.Trash"

# Use plain text mode for new TextEdit documents
defaults write com.apple.TextEdit RichText -bool false

# Open and save files as UTF-8 in TextEdit
defaults write com.apple.TextEdit PlainTextEncoding -int 4
defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4

# Enable the debug menu in Disk Utility
defaults write com.apple.DiskUtility DUDebugMenuEnabled -bool true
defaults write com.apple.DiskUtility advanced-image-options -bool true

# Auto-play videos when opened with QuickTime Player
defaults write com.apple.QuickTimePlayerX MGPlayMovieOnOpen -bool true

# Prevent Photos from opening automatically when devices are plugged in
defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true

# ********************************************************************************
# * Screenshots                                                                  *
# ********************************************************************************

# Save screenshots to the desktop
defaults write com.apple.screencapture location -string "${HOME}/Desktop"

# Save screenshots in PNG format (other options: BMP, GIF, JPG, PDF, TIFF)
defaults write com.apple.screencapture type -string "png"

# Disable shadow in screenshots
defaults write com.apple.screencapture disable-shadow -bool true

# ********************************************************************************
# * Terminal                                                                     *
# ********************************************************************************

# Only use UTF-8 in Terminal
defaults write com.apple.terminal StringEncodings -array 4

# Enable "focus follows mouse" for Terminal and all X11 apps
# i.e. hover over a window and start typing in it without clicking first
defaults write com.apple.terminal FocusFollowsMouse -bool true
defaults write org.x.X11 wm_ffm -bool true

# Disable Secure Keyboard Entry in Terminal
defaults write com.apple.terminal SecureKeyboardEntry -bool false

# Disable the annoying line marks
defaults write com.apple.Terminal ShowLineMarks -bool false

# Set theme and font
osascript <<EOD
tell application "Terminal"
    set terminalFile to POSIX file "$(find "$(dirname "$PWD")/resources" -name "*.terminal" | head -n 1)" as alias
    open terminalFile
    delay 1
    set themeName to name of current settings of window 1
    set font name of settings set themeName to "MesloLGS Nerd Font"
    set font size of settings set themeName to 12
    set default settings to settings set themeName
end tell
EOD


# ********************************************************************************
# * Activity Monitor                                                             *
# ********************************************************************************

# Show the main window when launching Activity Monitor
defaults write com.apple.ActivityMonitor OpenMainWindow -bool true

# Visualize CPU usage in the Activity Monitor Dock icon
defaults write com.apple.ActivityMonitor IconType -int 5

# Show all processes in Activity Monitor
defaults write com.apple.ActivityMonitor ShowCategory -int 0

# Sort Activity Monitor results by CPU usage
defaults write com.apple.ActivityMonitor SortColumn -string "CPUUsage"
defaults write com.apple.ActivityMonitor SortDirection -int 0

# ********************************************************************************
# * Safari                                                                       *
# ********************************************************************************

# Safari opens with a new window
defaults write com.apple.Safari AlwaysRestoreSessionAtLaunch -bool false

# New windows/tabs open with Start Page
defaults write com.apple.Safari NewWindowBehavior -int 4
defaults write com.apple.Safari NewTabBehavior -int 4

# Set Homepage to DuckDuckGo
defaults write com.apple.Safari HomePage -string "https://start.duckduckgo.com"

# Disable open "safe" files after downloading
defaults write com.apple.Safari AutoOpenSafeDownloads -bool false

# Set tab layout to compact
defaults write com.apple.Safari ShowStandaloneTabBar -bool false

# Automatically open pages in tabs instead of windows
defaults write com.apple.Safari TabCreationPolicy -int 1

# Set DuckDuckGo as the default search engine
defaults write com.apple.Safari SearchProviderShortName -string "DuckDuckGo"
defaults write com.apple.Safari PrivateSearchProviderShortName -string "DuckDuckGo"
defaults write com.apple.Safari WBSLastPrivateSearchEngineStringExplicitlyChosenByUserKey -string "com.duckduckgo"

# Include Safari search suggestions
defaults write com.apple.Safari UniversalSearchEnabled -bool true

# Warn about fraudulent websites
defaults write com.apple.Safari WarnAboutFraudulentWebsites -bool true

# Prevent cross-cite tracking and hide IP address
defaults write com.apple.Safari BlockStoragePolicy -int 2
defaults write com.apple.Safari WebKitPreferences.storageBlockingPolicy -bool true
defaults write com.apple.Safari WebKitStorageBlockingPolicy -bool true
defaults write com.apple.Safari WBSPrivacyProxyAvailabilityTraffic -int 33422572

# Show full website address
defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true

# Press Tab to highlight each item on a web page
defaults write com.apple.Safari WebKitTabToLinksPreferenceKey -bool true
defaults write com.apple.Safari WebKitPreferences.tabFocusesLinks -bool true

# Show colour in compact tab bar
defaults write com.apple.Safari NeverUseBackgroundColorInToolbar -bool false

# Use advanced tracking and fingerprint protection in all browsing
defaults write com.apple.Safari EnableEnhancedPrivacyInPrivateBrowsing -bool true
defaults write com.apple.Safari EnableEnhancedPrivacyInRegularBrowsing -bool true

# Use UTF-8 in Safari
defaults write com.apple.Safari WebKitPreferences.defaultTextEncodingName -string "utf-8"
defaults write com.apple.Safari WebKitDefaultTextEncodingName -string "utf-8"

# Show features for web developers
defaults write com.apple.Safari.SandboxBroker ShowDevelopMenu -bool true
defaults write com.apple.Safari IncludeDevelopMenu -bool true
defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
defaults write com.apple.Safari WebKitPreferences.developerExtrasEnabled -bool true

# Hide favourites bar
defaults write com.apple.Safari ShowFavoritesBar-v2 -bool false

# Disable Safari's thumbnail cache for History and Top Sites
defaults write com.apple.Safari DebugSnapshotsUpdatePolicy -int 2

# Make Safari's search banners default to Contains instead of Starts With
defaults write com.apple.Safari FindOnPageMatchesWordStartsOnly -bool false

# Remove useless icons from Safari’s bookmarks bar
defaults write com.apple.Safari ProxiesInBookmarksBar "()"

# Add a context menu item for showing the Web Inspector in web views
defaults write NSGlobalDomain WebKitDeveloperExtras -bool true

# Privacy: don't send search queries to Apple
defaults write com.apple.Safari UniversalSearchEnabled -bool false
defaults write com.apple.Safari SuppressSearchSuggestions -bool true

# Enable continuous spellchecking
defaults write com.apple.Safari WebContinuousSpellCheckingEnabled -bool true

# Disable auto-correct
defaults write com.apple.Safari WebAutomaticSpellingCorrectionEnabled -bool false

# Block pop-up windows
defaults write com.apple.Safari WebKitJavaScriptCanOpenWindowsAutomatically -bool false
defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically -bool false

# Disable auto-playing video
defaults write com.apple.Safari WebKitMediaPlaybackAllowsInline -bool false
defaults write com.apple.SafariTechnologyPreview WebKitMediaPlaybackAllowsInline -bool false
defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2AllowsInlineMediaPlayback -bool false
defaults write com.apple.SafariTechnologyPreview com.apple.Safari.ContentPageGroupIdentifier.WebKit2AllowsInlineMediaPlayback -bool false

# Update extensions automatically
defaults write com.apple.Safari InstallExtensionUpdatesAutomatically -bool true

# ********************************************************************************
# * App Store                                                                    *
# ********************************************************************************

# Enable Debug Menu in the App Store
defaults write com.apple.appstore ShowDebugMenu -bool true

# ********************************************************************************
# * Mail                                                                         *
# ********************************************************************************

# Disable send and reply animations in Mail
defaults write com.apple.mail DisableReplyAnimations -bool true
defaults write com.apple.mail DisableSendAnimations -bool true

# Copy email addresses as `foo@example.com` instead of `Foo Bar <foo@example.com>` in Mail
defaults write com.apple.mail AddressesIncludeNameOnPasteboard -bool false

# Display emails in threaded mode, sorted by date (oldest at the top)
defaults write com.apple.mail DraftsViewerAttributes -dict-add "DisplayInThreadedMode" -string "yes"
defaults write com.apple.mail DraftsViewerAttributes -dict-add "SortedDescending" -string "yes"
defaults write com.apple.mail DraftsViewerAttributes -dict-add "SortOrder" -string "received-date"

# Disable inline attachments (just show the icons)
defaults write com.apple.mail DisableInlineAttachmentViewing -bool true

# Disable automatic spell checking
defaults write com.apple.mail SpellCheckingBehavior -string "NoSpellCheckingEnabled"

# ********************************************************************************
# * Messages                                                                     *
# ********************************************************************************

# Disable automatic emoji substitution (i.e. use plain text smileys)
defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add "automaticEmojiSubstitutionEnablediMessage" -bool false

# Disable smart quotes as it's annoying for messages that contain code
defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add "automaticQuoteSubstitutionEnabled" -bool false

# Disable continuous spell checking
defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add "continuousSpellCheckingEnabled" -bool false

# ********************************************************************************
# * Raycast                                                                      *
# ********************************************************************************

# Set Raycast hotkey to Command + Space
defaults write com.raycast.macos raycastGlobalHotkey -string "Command-49"

# Don't show Raycast in the menu bar
defaults write com.raycast.macos "NSStatusItem Visible raycastIcon" -bool false

# Emoji Skin Tone (Medium)
defaults write com.raycast.macos  "emojiPicker_skinTone" -string "medium"

# Set Vim style navigation bindings
defaults write com.raycast.macos navigationCommandStyleIdentifierKey -string "vim"

# Import other settings and extensions
open -a "Raycast" "$(find "$(dirname "$PWD")/resources" -name "*.rayconfig" | head -n 1)"
osascript <<EOD
tell application "System Events"
    tell process "Raycast"
        keystroke return
    end tell
end tell
delay 1
tell application "System Events"
    tell process "Raycast"
        keystroke return
    end tell
end tell
EOD

# ********************************************************************************
# * Transmission                                                                 *
# ********************************************************************************

# Use `~/Torrents` to store incomplete downloads
defaults write org.m0k.transmission UseIncompleteDownloadFolder -bool true
defaults write org.m0k.transmission IncompleteDownloadFolder -string "${HOME}/Torrents"

# Use `~/Downloads` to store completed downloads
defaults write org.m0k.transmission DownloadLocationConstant -bool true

# Don't prompt for confirmation before downloading
defaults write org.m0k.transmission DownloadAsk -bool false
defaults write org.m0k.transmission MagnetOpenAsk -bool false

# Don't prompt for confirmation before removing non-downloading active transfers
defaults write org.m0k.transmission CheckRemoveDownloading -bool true

# Trash original torrent files
defaults write org.m0k.transmission DeleteOriginalTorrent -bool true

# Hide the donate message
defaults write org.m0k.transmission WarningDonate -bool false

# Hide the legal disclaimer
defaults write org.m0k.transmission WarningLegal -bool false

# IP block list
defaults write org.m0k.transmission BlocklistNew -bool true
defaults write org.m0k.transmission BlocklistURL -string "https://github.com/Naunter/BT_BlockLists/raw/master/bt_blocklists.gz"
defaults write org.m0k.transmission BlocklistAutoUpdate -bool true

# Randomize port on launch
defaults write org.m0k.transmission RandomPort -bool true

# Stop seeding when finished downloading
defaults write org.m0k.transmission RatioCheck -bool true
defaults write org.m0k.transmission RatioLimit -int 0

# Remove from the transfer list when seeding completes
defaults write org.m0k.transmission RemoveWhenFinishSeeding -bool true

# ********************************************************************************
# * Yabai                                                                        *
# ********************************************************************************

# Enable non-Apple-signed arm64e binaries for Apple Silicon
sudo nvram boot-args=-arm64e_preview_abi

# Configure scripting addition to inject into the Dock
echo "$(whoami) ALL=(root) NOPASSWD: sha256:$(shasum -a 256 $(which yabai) | cut -d " " -f 1) $(which yabai) --load-sa" | sudo tee /private/etc/sudoers.d/yabai

# ********************************************************************************
# * Kill some affected applications                                              *
# ********************************************************************************
if pgrep -x "Activity Monitor" > /dev/null; then killall "Activity Monitor"; fi
if pgrep -x "cfprefsd" > /dev/null; then killall "cfprefsd"; fi
if pgrep -x "Dock" > /dev/null; then killall "Dock"; fi
if pgrep -x "Finder" > /dev/null; then killall "Finder"; fi
if pgrep -x "Mail" > /dev/null; then killall "Mail"; fi
if pgrep -x "Messages" > /dev/null; then killall "Messages"; fi
if pgrep -x "Photos" > /dev/null; then killall "Photos"; fi
if pgrep -x "Safari" > /dev/null; then killall "Safari"; fi
if pgrep -x "SystemUIServer" > /dev/null; then killall "SystemUIServer"; fi
if pgrep -x "Terminal" > /dev/null; then killall "Terminal"; fi
if pgrep -x "Transmission" > /dev/null; then killall "Transmission"; fi

echo "Done. Please restart for everything to take effect."
