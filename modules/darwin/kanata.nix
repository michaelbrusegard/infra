{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  inherit (config.system) primaryUser;
  karabinerVhidManager = "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager";
  kanataApp = "/Applications/Kanata.app";
  stableKanata = "${kanataApp}/Contents/MacOS/kanata";
  kanataConfig = inputs.self + "/config/kanata/darwin.kbd";
  forceActivateKarabiner = ''
    primary_uid=$(/usr/bin/id -u ${primaryUser})
    launchctl asuser "$primary_uid" sudo -u ${primaryUser} \
      ${lib.escapeShellArg karabinerVhidManager} forceActivate || true
  '';
  ensureLaunchDaemon = label: ''
    if ! launchctl print system/org.nixos.${label} >/dev/null 2>&1; then
      echo "loading ${label} launch daemon..." >&2
      launchctl bootout system /Library/LaunchDaemons/org.nixos.${label}.plist >/dev/null 2>&1 || true
      launchctl bootstrap system /Library/LaunchDaemons/org.nixos.${label}.plist
      launchctl enable system/org.nixos.${label}
    fi
  '';
  # Kanata only grabs keyboards that are connected when it starts; a keyboard
  # plugged in later is never seized. Restart kanata when the set of external
  # keyboards changes so it re-grabs everything currently connected.
  #
  # Restarting kanata re-fires the launch event (its Karabiner virtual
  # keyboard reappears and the seized devices' event services are re-created),
  # so the state file must only change when a device genuinely comes or goes:
  # fingerprint by vendor/product/location only — hidutil row order, registry
  # IDs, and event-service rows all flap with kanata's seize/release cycle.
  # The kanata pid is tracked alongside so a keyboard replugged after kanata
  # itself crashed and respawned still triggers a re-grab.
  kanataKeyboardWatcher = pkgs.writeShellScript "kanata-keyboard-watcher" ''
    sleep 1
    state=/var/run/org.nixos.kanata.keyboards
    kanata_pid() {
      /bin/launchctl print system/org.nixos.kanata 2>/dev/null \
        | /usr/bin/grep -m1 '[[:space:]]pid = ' | /usr/bin/awk '{print $3}'
    }
    current=$(/usr/bin/hidutil list --matching '{"DeviceUsagePage":1,"DeviceUsage":6}' \
      | /usr/bin/grep '^0x' \
      | /usr/bin/grep -v 'Apple Internal Keyboard' \
      | /usr/bin/grep -v 'Karabiner' \
      | /usr/bin/awk '{print $1, $2, $3}' | /usr/bin/sort -u || true)
    [ -n "$current" ] || exit 0
    hash=$(printf '%s' "$current" | /sbin/md5 -q)
    new="$hash $(kanata_pid)"
    old=$(/bin/cat "$state" 2>/dev/null || true)
    if [ "$new" != "$old" ]; then
      echo "$(date '+%F %T') keyboard set or kanata pid changed, restarting kanata"
      /bin/launchctl kickstart -k system/org.nixos.kanata
      pid=""
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        sleep 1
        pid=$(kanata_pid)
        [ -n "$pid" ] && break
      done
      printf '%s %s' "$hash" "$pid" > "$state"
    fi
  '';
in {
  environment.systemPackages = [pkgs.kanata-with-cmd];
  system.activationScripts.postActivation.text = ''
    install -d -m 755 ${lib.escapeShellArg "${kanataApp}/Contents/MacOS"}
    install -d -m 755 ${lib.escapeShellArg "${kanataApp}/Contents/Resources"}
    install -m 755 ${pkgs.kanata-with-cmd}/bin/kanata ${stableKanata}
    cat > ${lib.escapeShellArg "${kanataApp}/Contents/Info.plist"} <<'EOF'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
      "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleExecutable</key>
      <string>kanata</string>
      <key>CFBundleIdentifier</key>
      <string>org.nixos.kanata</string>
      <key>CFBundleName</key>
      <string>Kanata</string>
      <key>CFBundlePackageType</key>
      <string>APPL</string>
      <key>CFBundleShortVersionString</key>
      <string>1.11.0</string>
      <key>CFBundleVersion</key>
      <string>1.11.0</string>
    </dict>
    </plist>
    EOF
    codesign --force --deep --sign - ${lib.escapeShellArg kanataApp} >/dev/null

    chmod 755 /Library/Logs/Kanata

    ${ensureLaunchDaemon "karabiner-vhiddaemon"}
    ${ensureLaunchDaemon "karabiner-vhidmanager"}
    ${forceActivateKarabiner}
    ${ensureLaunchDaemon "kanata"}
    ${ensureLaunchDaemon "kanata-keyboard-watcher"}
  '';

  launchd.daemons = {
    kanata = {
      serviceConfig = {
        ProgramArguments = [
          stableKanata
          "--no-wait"
          "-c"
          "${kanataConfig}"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardErrorPath = "/Library/Logs/Kanata/kanata.err.log";
        StandardOutPath = "/Library/Logs/Kanata/kanata.out.log";
      };
    };
    karabiner-vhiddaemon = {
      serviceConfig = {
        ProgramArguments = [
          "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
        ];
        RunAtLoad = true;
        KeepAlive = true;
      };
    };
    karabiner-vhidmanager = {
      serviceConfig = {
        ProgramArguments = [
          "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"
          "activate"
        ];
        RunAtLoad = true;
      };
    };
    kanata-keyboard-watcher = {
      serviceConfig = {
        ProgramArguments = ["${kanataKeyboardWatcher}"];
        LaunchEvents = {
          "com.apple.iokit.matching" = {
            "keyboard-attached" = {
              IOMatchLaunchStream = true;
              IOProviderClass = "IOHIDDevice";
              IOPropertyMatch = {
                PrimaryUsagePage = 1;
                PrimaryUsage = 6;
              };
            };
          };
        };
        StandardErrorPath = "/Library/Logs/Kanata/keyboard-watcher.err.log";
        StandardOutPath = "/Library/Logs/Kanata/keyboard-watcher.out.log";
      };
    };
  };
}
