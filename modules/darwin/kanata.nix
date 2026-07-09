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
  kanataWrapper = pkgs.writeShellScript "kanata-darwin" ''
    ${forceActivateKarabiner}
    sleep 2
    exec ${lib.escapeShellArg stableKanata} --no-wait -c ${kanataConfig}
  '';
  ensureLaunchDaemon = label: ''
    if ! launchctl print system/org.nixos.${label} >/dev/null 2>&1; then
      echo "loading ${label} launch daemon..." >&2
      launchctl bootout system /Library/LaunchDaemons/org.nixos.${label}.plist >/dev/null 2>&1 || true
      launchctl bootstrap system /Library/LaunchDaemons/org.nixos.${label}.plist
      launchctl enable system/org.nixos.${label}
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
  '';

  launchd.daemons = {
    kanata = {
      command = "${kanataWrapper}";
      serviceConfig = {
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
  };
}
