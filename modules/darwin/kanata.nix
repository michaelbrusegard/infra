{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  inherit (config.system) primaryUser;
  karabinerVhidManager = "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager";
  stableKanata = "/usr/local/libexec/kanata/kanata";
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
    install -d -m 755 /usr/local/libexec/kanata
    install -m 755 ${pkgs.kanata-with-cmd}/bin/kanata ${stableKanata}

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
